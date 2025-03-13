module Vira.Lib.LogStream where

import Control.Concurrent.STM (
  TChan,
  dupTChan,
  newBroadcastTChanIO,
  writeTChan,
 )
import Control.Exception (catch, throwIO)
import Data.Text.IO (hGetLine, hPutStrLn)
import GHC.IO.Exception (IOError)
import System.IO.Error (ioeGetErrorType, isEOFErrorType)

-- | Data type representing a log stream with history and real-time updates
data LogStream = LogStream
  { logHistory :: TVar [Text] -- Thread-safe list of all past log entries
  , logChannel :: TChan Text -- Broadcast channel for new log entries
  }

-- | Create a new log stream
newLogStream :: IO LogStream
newLogStream = do
  history <- newTVarIO [] -- Initialize with empty history
  chan <- newBroadcastTChanIO -- Create a broadcast channel
  pure $ LogStream history chan

-- | Write a log entry to the stream
writeLog :: LogStream -> Text -> IO ()
writeLog (LogStream history chan) entry = atomically $ do
  -- Append to history (in reverse order for efficiency, prepending)
  modifyTVar' history (entry :)
  -- Broadcast to all subscribed readers
  writeTChan chan entry

-- | Subscribe to the log stream, getting history and future updates
subscribeLog :: LogStream -> IO (TChan Text)
subscribeLog (LogStream history chan) = atomically $ do
  -- Get a duplicate channel for this reader
  readerChan <- dupTChan chan
  -- Pre-populate with current history (reversed to maintain order)
  pastEntries <- reverse <$> readTVar history
  mapM_ (writeTChan readerChan) pastEntries
  return readerChan

-- | Read from a Handle and write to both a file and a LogStream
redirectOutput :: Handle -> Handle -> LogStream -> IO ()
redirectOutput inputHandle fileHandle stream =
  do
    forever $ do
      line <- hGetLine inputHandle
      hPutStrLn fileHandle line -- Write to file
      writeLog stream line -- Write to log stream
    `catch` (\e -> if isEOFError e then pass else throwIO e)
  where
    isEOFError :: IOError -> Bool
    isEOFError = isEOFErrorType . ioeGetErrorType
