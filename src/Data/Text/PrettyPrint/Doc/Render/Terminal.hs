{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Render 'SimpleDoc' in a terminal.
module Data.Text.PrettyPrint.Doc.Render.Terminal (
    -- * Conversion to ANSI-infused 'Text'
    renderLazy, renderStrict,

    -- * Render directly to the terminal
    renderIO,

    -- ** Convenience
    --
    -- | These functions use default parameters, and handle the most common use
    -- cases.
    putDoc, hPutDoc, putDocW, hPutDocW,
) where



import           Control.Monad
import           Data.Functor
import           Data.Maybe
import           Data.Monoid
import           Data.Text              (Text)
import qualified Data.Text              as T
import qualified Data.Text.Lazy         as LT
import qualified Data.Text.Lazy.Builder as LTB
import qualified Data.Text.Lazy.IO      as LT
import           System.Console.ANSI
import           System.IO              (Handle, stdout)

import Data.Text.PrettyPrint.Doc
import Data.Text.PrettyPrint.Doc.Render.RenderM



-- $setup
-- >>> :set -XOverloadedStrings
-- >>> import qualified Data.Text.Lazy.IO as TL
-- >>> import qualified Data.Text.Lazy as TL
-- >>> import Data.Text.PrettyPrint.Doc.Render.Terminal



-- | @('renderLazy' doc)@ takes the output @doc@ from a rendering function
-- and transforms it to lazy text, including ANSI styling directives for things
-- like colorization.
--
-- ANSI color information will be discarded by this function unless you are
-- running on a Unix-like operating system. This is due to a technical
-- limitation in Windows ANSI support.
--
-- With a bit of trickery to make the ANSI codes printable, here is an example
-- that would render coloured in an ANSI terminal:
--
-- >>> let render = TL.putStrLn . TL.replace "\ESC" "\\e" . renderLazy . layoutPretty 0.4 80
-- >>> let doc = red ("red" <+> blue ("blue" <+> bold "bold" <+> "blue") <+> "red")
-- >>> render (plain doc)
-- red blue bold blue red
-- >>> render doc
-- \e[0;91mred \e[0;94mblue \e[0;94;1mbold\e[0;94m blue\e[0;91m red\e[0m
--
-- Run the above via @echo -e '...'@ in your terminal to see the colouring.
renderLazy :: SimpleDoc -> LT.Text
renderLazy doc
  = let (resultBuilder, remainingStyles) = execRenderM [emptyStyle] (build doc)
    in case remainingStyles of
        [] -> error "There is no empty style left at the end of rendering\
                    \ (but there should be). Please report this as a bug."
        [_] -> LTB.toLazyText resultBuilder
        xs -> error ("There are " <> show (length xs) <> " styles left at the\
                     \end of rendering (there should be only 1). Please report\
                     \ this as a bug.")

build :: SimpleDoc -> RenderM LTB.Builder CombinedStyle ()
build = \case
    SFail -> error "@SFail@ can not appear uncaught in a rendered @SimpleDoc@"
    SEmpty -> pure ()
    SChar c x -> do writeResult (LTB.singleton c)
                    build x
    SText t x -> do writeResult (LTB.fromText t)
                    build x
    SLine i x -> do writeResult (LTB.singleton '\n')
                    writeResult (LTB.fromText (T.replicate i " "))
                    build x
    SStylePush s x -> do
        -- Get current style
        currentStyle <- unsafePeekStyle
        let newStyle = currentStyle `addStyle` s
        writeResult (styleToBuilder newStyle)
        pushStyle newStyle
        build x
    SStylePop x -> do
        _currentStyle <- unsafePopStyle
        newStyle <- unsafePeekStyle
        writeResult (styleToBuilder newStyle)
        build x

styleToBuilder :: CombinedStyle -> LTB.Builder
styleToBuilder = LTB.fromString . setSGRCode . stylesToSgrs

data CombinedStyle = CombinedStyle
    (Maybe (SIntensity, SColor)) -- Foreground
    (Maybe (SIntensity, SColor)) -- Background
    Bool                         -- Bold
    Bool                         -- Italics
    Bool                         -- Underlining

addStyle :: CombinedStyle -> Style -> CombinedStyle
addStyle (CombinedStyle m'fg m'bg b i u) = \case
    SItalicized               -> CombinedStyle m'fg m'bg b True u
    SBold                     -> CombinedStyle m'fg m'bg True i u
    SUnderlined               -> CombinedStyle m'fg m'bg b i True
    SColor SForeground dv col -> CombinedStyle (Just (dv, col)) m'bg b i u
    SColor SBackground dv col -> CombinedStyle m'fg (Just (dv, col)) b i u

emptyStyle :: CombinedStyle
emptyStyle = CombinedStyle Nothing Nothing False False False

stylesToSgrs :: CombinedStyle -> [SGR]
stylesToSgrs (CombinedStyle m'fg m'bg b i u) = catMaybes
    [ Just Reset
    , fmap (\(intensity, color) -> SetColor Foreground (convertIntensity intensity) (convertColor color)) m'fg
    , fmap (\(intensity, color) -> SetColor Background (convertIntensity intensity) (convertColor color)) m'bg
    , guard b $> SetConsoleIntensity BoldIntensity
    , guard i $> SetItalicized True
    , guard u $> SetUnderlining SingleUnderline
    ]
  where
    convertIntensity :: SIntensity -> ColorIntensity
    convertIntensity = \case
        SVivid -> Vivid
        SDull  -> Dull

    convertColor :: SColor -> Color
    convertColor = \case
        SBlack   -> Black
        SRed     -> Red
        SGreen   -> Green
        SYellow  -> Yellow
        SBlue    -> Blue
        SMagenta -> Magenta
        SCyan    -> Cyan
        SWhite   -> White



-- | @('renderStrict' sdoc)@ takes the output @sdoc@ from a rendering and
-- transforms it to strict text.
renderStrict :: SimpleDoc -> Text
renderStrict = LT.toStrict . renderLazy



-- | @('renderIO' h sdoc)@ writes @sdoc@ to the file @h@.
renderIO :: Handle -> SimpleDoc -> IO ()
renderIO h sdoc = LT.hPutStrLn h (renderLazy sdoc)

-- | @putDoc doc@ prettyprints document @doc@ to standard output, with a page
-- width of 80 characters and a ribbon width of 32 characters (see
-- 'layoutPretty' for documentation of those values.)
--
-- >>> putDoc ("hello" <+> "world")
-- hello world
--
-- @
-- 'putDoc' = 'hPutDoc' 'stdout'
-- @
putDoc :: Doc -> IO ()
putDoc = hPutDoc stdout

-- | 'putDoc', but with a page width parameter.
putDocW :: Int -> Doc -> IO ()
putDocW = hPutDocW stdout

-- | Like 'putDoc', but instead of using 'stdout', print to a user-provided
-- handle, e.g. a file or a socket. Uses a line length of 80, and a ribbon width
-- of 32 characters (see 'layoutPretty' for documentation of those values).
--
-- > main = withFile "someFile.txt" (\h -> hPutDoc h (vcat ["vertical", "text"]))
--
-- @
-- 'hPutDoc' h doc = 'renderIO' h ('layoutPretty' 0.4 80 doc)
-- @
hPutDoc :: Handle -> Doc -> IO ()
hPutDoc h doc = renderIO h (layoutPretty 0.4 80 doc)

-- | 'hPutDocW', but with with ribbon fraction/page width parameters.
hPutDocW :: Handle -> Int -> Doc -> IO ()
hPutDocW h w doc = renderIO h (layoutPretty 1.0 w doc)