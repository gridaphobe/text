{-# LANGUAGE BangPatterns #-}

-- |
-- Module      : Data.Text.Encoding.Fusion
-- Copyright   : (c) Tom Harper 2008-2009,
--               (c) Bryan O'Sullivan 2009,
--               (c) Duncan Coutts 2009
--
-- License     : BSD-style
-- Maintainer  : rtharper@aftereternity.co.uk, bos@serpentine.com,
--               duncan@haskell.org
-- Stability   : experimental
-- Portability : portable
--
-- Fusible 'Stream'-oriented functions for converting between 'Text'
-- and several common encodings.

module Data.Text.Encoding.Fusion
    (
    -- * Streaming
      streamASCII
    , streamUtf8
    , streamUtf16LE
    , streamUtf16BE
    , streamUtf32LE
    , streamUtf32BE

    -- * Unstreaming
    , unstream

    , module Data.Text.Encoding.Fusion.Common
    ) where

import Control.Exception (assert)
import Data.Bits (shiftL)
import Data.ByteString as B
import Data.ByteString.Internal (ByteString(..), mallocByteString, memcpy)
import Data.Text.Fusion (Step(..), Stream(..))
import Data.Text.Encoding.Fusion.Common
import Data.Text.UnsafeChar (unsafeChr, unsafeChr8, unsafeChr32)
import Data.Word (Word8, Word16, Word32)
import Foreign.ForeignPtr (withForeignPtr, ForeignPtr)
import Foreign.Storable (pokeByteOff)
import System.IO.Unsafe (unsafePerformIO)
import qualified Data.ByteString as B
import qualified Data.ByteString.Unsafe as B
import qualified Data.Text.Encoding.Utf8 as U8
import qualified Data.Text.Encoding.Utf16 as U16
import qualified Data.Text.Encoding.Utf32 as U32

streamASCII :: ByteString -> Stream Char
streamASCII bs = Stream next 0 l
    where
      l = B.length bs
      {-# INLINE next #-}
      next i
          | i >= l    = Done
          | otherwise = Yield (unsafeChr8 x1) (i+1)
          where
            x1 = B.unsafeIndex bs i
{-# INLINE [0] streamASCII #-}

-- | /O(n)/ Convert a 'ByteString' into a 'Stream Char', using UTF-8
-- encoding.
streamUtf8 :: ByteString -> Stream Char
streamUtf8 bs = Stream next 0 l
    where
      l = B.length bs
      {-# INLINE next #-}
      next i
          | i >= l = Done
          | U8.validate1 x1 = Yield (unsafeChr8 x1) (i+1)
          | i+1 < l && U8.validate2 x1 x2 = Yield (U8.chr2 x1 x2) (i+2)
          | i+2 < l && U8.validate3 x1 x2 x3 = Yield (U8.chr3 x1 x2 x3) (i+3)
          | i+3 < l && U8.validate4 x1 x2 x3 x4 = Yield (U8.chr4 x1 x2 x3 x4) (i+4)
          | otherwise = encodingError "UTF-8"
          where
            x1 = idx i
            x2 = idx (i + 1)
            x3 = idx (i + 2)
            x4 = idx (i + 3)
            idx = B.unsafeIndex bs
{-# INLINE [0] streamUtf8 #-}

-- | /O(n)/ Convert a 'ByteString' into a 'Stream Char', using little
-- endian UTF-16 encoding.
streamUtf16LE :: ByteString -> Stream Char
streamUtf16LE bs = Stream next 0 l
    where
      l = B.length bs
      {-# INLINE next #-}
      next i
          | i >= l                         = Done
          | i+1 < l && U16.validate1 x1    = Yield (unsafeChr x1) (i+2)
          | i+3 < l && U16.validate2 x1 x2 = Yield (U16.chr2 x1 x2) (i+4)
          | otherwise = encodingError "UTF-16LE"
          where
            x1    = idx i       + (idx (i + 1) `shiftL` 8)
            x2    = idx (i + 2) + (idx (i + 3) `shiftL` 8)
            idx = fromIntegral . B.unsafeIndex bs :: Int -> Word16
{-# INLINE [0] streamUtf16LE #-}

-- | /O(n)/ Convert a 'ByteString' into a 'Stream Char', using big
-- endian UTF-16 encoding.
streamUtf16BE :: ByteString -> Stream Char
streamUtf16BE bs = Stream next 0 l
    where
      l = B.length bs
      {-# INLINE next #-}
      next i
          | i >= l                         = Done
          | i+1 < l && U16.validate1 x1    = Yield (unsafeChr x1) (i+2)
          | i+3 < l && U16.validate2 x1 x2 = Yield (U16.chr2 x1 x2) (i+4)
          | otherwise = encodingError "UTF16-BE"
          where
            x1    = (idx i `shiftL` 8)       + idx (i + 1)
            x2    = (idx (i + 2) `shiftL` 8) + idx (i + 3)
            idx = fromIntegral . B.unsafeIndex bs :: Int -> Word16
{-# INLINE [0] streamUtf16BE #-}

-- | /O(n)/ Convert a 'ByteString' into a 'Stream Char', using big
-- endian UTF-32 encoding.
streamUtf32BE :: ByteString -> Stream Char
streamUtf32BE bs = Stream next 0 l
    where
      l = B.length bs
      {-# INLINE next #-}
      next i
          | i >= l                    = Done
          | i+3 < l && U32.validate x = Yield (unsafeChr32 x) (i+4)
          | otherwise                 = encodingError "UTF-32BE"
          where
            x     = shiftL x1 24 + shiftL x2 16 + shiftL x3 8 + x4
            x1    = idx i
            x2    = idx (i+1)
            x3    = idx (i+2)
            x4    = idx (i+3)
            idx = fromIntegral . B.unsafeIndex bs :: Int -> Word32
{-# INLINE [0] streamUtf32BE #-}

-- | /O(n)/ Convert a 'ByteString' into a 'Stream Char', using little
-- endian UTF-32 encoding.
streamUtf32LE :: ByteString -> Stream Char
streamUtf32LE bs = Stream next 0 l
    where
      l = B.length bs
      {-# INLINE next #-}
      next i
          | i >= l                    = Done
          | i+3 < l && U32.validate x = Yield (unsafeChr32 x) (i+4)
          | otherwise                 = encodingError "UTF-32LE"
          where
            x     = shiftL x4 24 + shiftL x3 16 + shiftL x2 8 + x1
            x1    = idx i
            x2    = idx $ i+1
            x3    = idx $ i+2
            x4    = idx $ i+3
            idx = fromIntegral . B.unsafeIndex bs :: Int -> Word32
{-# INLINE [0] streamUtf32LE #-}

-- | /O(n)/ Convert a 'Stream' 'Word8' to a 'ByteString'.
unstream :: Stream Word8 -> ByteString
unstream (Stream next s0 len) = unsafePerformIO $ do
    fp0 <- mallocByteString len
    loop fp0 len 0 s0
    where
      loop !fp !n !off !s = case next s of
          Done -> trimUp fp n off
          Skip s' -> loop fp n off s'
          Yield x s'
              | n == off -> realloc fp n off s' x
              | otherwise -> do
            withForeignPtr fp $ \p -> pokeByteOff p off x
            loop fp n (off+1) s'
      {-# NOINLINE realloc #-}
      realloc fp n off s x = do
        let n' = n+n
        fp' <- copy0 fp n n'
        withForeignPtr fp' $ \p -> pokeByteOff p off x
        loop fp' n' (off+1) s
      {-# NOINLINE trimUp #-}
      trimUp fp _ off = return $! PS fp 0 off
      copy0 :: ForeignPtr Word8 -> Int -> Int -> IO (ForeignPtr Word8)
      copy0 !src !srcLen !destLen = assert (srcLen <= destLen) $ do
          dest <- mallocByteString destLen
          withForeignPtr src  $ \src'  ->
              withForeignPtr dest $ \dest' ->
                  memcpy dest' src' (fromIntegral destLen)
          return dest

encodingError :: String -> a
encodingError encoding =
    error $ "Data.Text.Encoding.Fusion: Bad " ++ encoding ++ " stream"
