module LLVM.Internal.RawOStream where

import LLVM.Prelude

import Control.Monad.AnyCont
import Control.Monad.Error.Class
import Control.Monad.IO.Class
import Control.Monad.Trans.Except

import Unsafe.Coerce
import Data.IORef
import Foreign.C
import Foreign.Ptr

import qualified  LLVM.Internal.FFI.RawOStream as FFI

import LLVM.Internal.Coding
import LLVM.Internal.Inject
import LLVM.Internal.String ()

withFileRawOStream ::
  (Inject String e, MonadError e m, MonadAnyCont IO m, MonadIO m)
  => String
  -> Bool
  -> Bool
  -> (Ptr FFI.RawOStream -> ExceptT String IO ())
  -> m ()
withFileRawOStream path excl text c = do
  path <- encodeM path
  excl <- encodeM excl
  text <- encodeM text
  msgPtr <- alloca
  errorRef <- liftIO $ newIORef undefined
  succeeded <- decodeM =<< (liftIO $ FFI.withFileRawOStream path excl text msgPtr $ \os -> do
                              r <- runExceptT (c os)
                              writeIORef errorRef r)
  unless succeeded $ do
    s <- decodeM msgPtr
    throwError $ inject (s :: String)
  e <- liftIO $ readIORef errorRef
  either (throwError . inject) return e

withFileRawPWriteStream ::  (Inject String e, MonadError e m, MonadAnyCont IO m, MonadIO m)
                            => String
                            -> Bool
                            -> Bool
                            -> (Ptr FFI.RawPWriteStream -> ExceptT String IO ())
                            -> m ()
withFileRawPWriteStream path excl text c = withFileRawOStream path excl text (unsafeCoerce c)

withBufferRawOStream ::
  (Inject String e, MonadError e m, MonadIO m, DecodeM IO a (Ptr CChar, CSize))
  => (Ptr FFI.RawOStream -> ExceptT String IO ())
  -> m a
withBufferRawOStream c = do
  resultRef <- liftIO $ newIORef Nothing
  errorRef <- liftIO $ newIORef undefined
  let saveBuffer :: Ptr CChar -> CSize -> IO ()
      saveBuffer start size = do
        r <- decodeM (start, size)
        writeIORef resultRef (Just r)
      saveError os = do
        r <- runExceptT (c os)
        writeIORef errorRef r
  liftIO $ FFI.withBufferRawOStream saveBuffer saveError
  e <- liftIO $ readIORef errorRef
  case e of
    Left e -> throwError $ inject e
    _ -> do
      Just r <- liftIO $ readIORef resultRef
      return r

withBufferRawPWriteStream ::
  (Inject String e, MonadError e m, MonadIO m, DecodeM IO a (Ptr CChar, CSize))
  => (Ptr FFI.RawPWriteStream -> ExceptT String IO ())
  -> m a
withBufferRawPWriteStream c = do
  withBufferRawOStream (unsafeCoerce c)
