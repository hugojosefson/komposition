{-# LANGUAGE ConstraintKinds    #-}
{-# LANGUAGE DataKinds          #-}
{-# LANGUAGE FlexibleContexts   #-}
{-# LANGUAGE GADTs              #-}
{-# LANGUAGE KindSignatures     #-}
{-# LANGUAGE LambdaCase         #-}
{-# LANGUAGE OverloadedStrings  #-}
{-# LANGUAGE RankNTypes         #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TemplateHaskell    #-}
{-# LANGUAGE TypeFamilies       #-}
{-# LANGUAGE TypeInType         #-}
{-# LANGUAGE TypeOperators      #-}

module Komposition.UserInterface where

import           Komposition.Prelude            hiding (State)

import           Control.Lens
import           Data.Row.Records
import           Data.Time.Clock
import           Motor.FSM                      hiding (Delete)
import           Pipes
import           Pipes.Safe                     (SafeT)

import           Komposition.Composition.Insert
import           Komposition.Focus
import           Komposition.History
import           Komposition.KeyMap
import           Komposition.Library
import           Komposition.MediaType
import           Komposition.Progress
import           Komposition.Project
import           Komposition.VideoSettings

data Mode
  = WelcomeScreenMode
  | TimelineMode
  | LibraryMode
  | ImportMode

data SMode m where
  SWelcomeScreenMode :: SMode WelcomeScreenMode
  STimelineMode :: SMode TimelineMode
  SLibraryMode :: SMode LibraryMode
  SImportMode :: SMode ImportMode

modeTitle :: SMode m -> Text
modeTitle = \case
  SWelcomeScreenMode -> "Welcome Screen Mode"
  STimelineMode -> "Timeline Mode"
  SLibraryMode  -> "Library Mode"
  SImportMode   -> "Import Mode"

class ReturnsToTimeline (mode :: Mode)

instance ReturnsToTimeline WelcomeScreenMode
instance ReturnsToTimeline LibraryMode
instance ReturnsToTimeline ImportMode

data InsertType
  = InsertComposition
  | InsertClip (Maybe MediaType)
  | InsertGap (Maybe MediaType)
  deriving (Show, Eq, Ord)

data Command (mode :: Mode) where
  Cancel :: Command mode
  Help :: Command mode

  FocusCommand :: FocusCommand -> Command TimelineMode
  JumpFocus :: Focus SequenceFocusType -> Command TimelineMode
  InsertCommand :: InsertType -> InsertPosition -> Command TimelineMode
  Split :: Command TimelineMode
  Delete :: Command TimelineMode
  Import :: Command TimelineMode
  Render :: Command TimelineMode
  Preview :: Command TimelineMode
  Undo :: Command TimelineMode
  Redo :: Command TimelineMode
  SaveProject :: Command TimelineMode
  CloseProject :: Command TimelineMode
  Exit :: Command TimelineMode

deriving instance Eq (Command mode)

deriving instance Ord (Command mode)

commandName :: Command mode -> Text
commandName =
  \case
    Cancel -> "Cancel"
    Help -> "Show Help"
    FocusCommand cmd ->
      case cmd of
        FocusUp    -> "Move Focus Up"
        FocusDown  -> "Move Focus Down"
        FocusLeft  -> "Move Focus Left"
        FocusRight -> "Move Focus Right"
    JumpFocus _ -> "Jump Focus To"
    InsertCommand insertType insertPosition ->
      mconcat
        [ insertTypeName insertType
        , " ("
        , insertPositionName insertPosition
        , ")"
        ]
    Split -> "Split"
    Delete -> "Delete"
    Import -> "Import Assets"
    Render -> "Render"
    Preview -> "Preview"
    Undo -> "Undo"
    Redo -> "Redo"
    SaveProject -> "Save"
    CloseProject -> "Close"
    Exit -> "Exit"
  where
    insertTypeName :: InsertType -> Text
    insertTypeName =
      \case
        InsertClip Nothing -> "Insert Clip"
        InsertGap Nothing -> "Insert Gap"
        InsertClip (Just Video) -> "Insert Video Clip"
        InsertGap (Just Video) -> "Insert Video Gap"
        InsertClip (Just Audio) -> "Insert Audio Clip"
        InsertGap (Just Audio) -> "Insert Audio Gap"
        InsertComposition -> "Insert Composition"
    insertPositionName :: InsertPosition -> Text
    insertPositionName =
      \case
        LeftMost -> "Leftmost"
        LeftOf -> "Left of"
        RightOf -> "Right of"
        RightMost -> "Rightmost"

data Event mode where
  CommandKeyMappedEvent :: Command mode -> Event mode
  CreateNewProjectClicked :: Event WelcomeScreenMode
  OpenExistingProjectClicked :: Event WelcomeScreenMode
  ZoomLevelChanged :: ZoomLevel -> Event TimelineMode
  ImportFileSelected :: Maybe FilePath -> Event ImportMode
  ImportAutoSplitSet :: Bool -> Event ImportMode
  ImportClicked :: Event ImportMode
  LibraryAssetsSelected :: SMediaType mt -> [Asset mt] -> Event LibraryMode
  LibrarySelectionConfirmed :: Event LibraryMode

data ModeKeyMap where
  ModeKeyMap :: forall mode. Ord (Command mode) => SMode mode -> KeyMap (Command mode) -> ModeKeyMap

type KeyMaps = forall mode. SMode mode -> KeyMap (Event mode)

class Enum c => DialogChoice c where
  toButtonLabel :: c -> Text

data FileChooserType
  = File
  | Directory

data FileChooserMode
  = Open FileChooserType
  | Save FileChooserType

data PromptMode ret where
  NumberPrompt :: (Double, Double) -> PromptMode Double
  TextPrompt :: PromptMode Text

newtype ZoomLevel = ZoomLevel Double

data TimelineModel = TimelineModel
  { _existingProject :: ExistingProject
  , _currentFocus    :: Focus SequenceFocusType
  , _statusMessage   :: Maybe Text
  , _zoomLevel       :: ZoomLevel
  }

makeLenses ''TimelineModel

currentProject :: TimelineModel -> Project
currentProject = current . view (existingProject . projectHistory)

data ImportFileModel = ImportFileModel
  { autoSplitValue     :: Bool
  , autoSplitAvailable :: Bool
  }

data SelectAssetsModel mt = SelectAssetsModel
  { mediaType      :: SMediaType mt
  , allAssets      :: NonEmpty (Asset mt)
  , selectedAssets :: [Asset mt]
  }

data Ok = Ok deriving (Eq, Enum)

instance DialogChoice Ok where
  toButtonLabel Ok = "OK"

class MonadFSM m =>
      UserInterface m where
  type State m :: Mode -> Type

  start ::
       Name n
    -> KeyMaps
    -> Actions m '[ n !+ State m WelcomeScreenMode] r ()
  updateWelcomeScreen
    :: Name n
    -> Actions m '[ n := State m WelcomeScreenMode !--> State m WelcomeScreenMode] r ()
  returnToWelcomeScreen
    :: Name n
    -> Actions m '[ n := State m TimelineMode !--> State m WelcomeScreenMode] r ()
  updateTimeline
    :: Name n
    -> TimelineModel
    -> Actions m '[ n := State m TimelineMode !--> State m TimelineMode] r ()
  returnToTimeline
    :: ReturnsToTimeline mode
    => Name n
    -> TimelineModel
    -> Actions m '[ n := State m mode !--> State m TimelineMode] r ()

  enterLibrary
    :: Name n
    -> SelectAssetsModel mt
    -> Actions m '[ n := State m TimelineMode !--> State m LibraryMode] r ()
  updateLibrary
    :: Name n
    -> SelectAssetsModel mt
    -> Actions m '[ n := State m LibraryMode !--> State m LibraryMode] r ()
  enterImport
    :: Name n
    -> ImportFileModel
    -> Actions m '[ n := State m TimelineMode !--> State m ImportMode] r ()
  updateImport
    :: Name n
    -> ImportFileModel
    -> Actions m '[ n := State m ImportMode !--> State m ImportMode] r ()
  nextEvent
    :: Name n
    -> Actions m '[ n := Remain (State m t)] r (Event t)
  nextEventOrTimeout
    :: Name n
    -> DiffTime
    -> Actions m '[ n := Remain (State m t)] r (Maybe (Event t))
  beep :: Name n -> Actions m '[] r ()
  dialog
    :: DialogChoice c
    => Name n
    -> Text -- ^ Dialog window title.
    -> Text -- ^ Dialog message.
    -> [c] -- ^ Choices of the dialog, rendered as buttons.
    -> Actions m '[ n := Remain (State m t)] r (Maybe c)
  prompt
    :: Name n
    -> Text -- ^ Prompt window title.
    -> Text -- ^ Prompt message.
    -> Text -- ^ Button text for confirming the choice.
    -> PromptMode ret -- ^ Type of prompt, decides the return value type.
    -> Actions m '[ n := Remain (State m t)] r (Maybe ret)
  chooseFile
    :: Name n
    -> FileChooserMode
    -> Text -- ^ Dialog window title.
    -> FilePath
    -> Actions m '[ n := Remain (State m t)] r (Maybe FilePath)
  progressBar
    :: Exception e
    => (Name n)
    -> Text -- ^ Progress window title.
    -> Producer ProgressUpdate (SafeT IO) a -- ^ Progress updates producer.
    -> Actions m '[ n := Remain (State m t)] r (Maybe (Either e a))
  previewStream
    :: Name n
    -> Text -- ^ URI to stream
    -> Producer ProgressUpdate (SafeT IO) () -- ^ Streaming process
    -> VideoSettings
    -> Actions m '[ n := Remain (State m t)] r (Maybe ())
  help
    :: Name n
    -> [ModeKeyMap]
    -> Actions m '[ n := Remain (State m t)] r ()
  exit :: Name n -> Actions m '[ n !- State m s] r ()

-- | Convenient type for actions that transition from one mode (of
-- type 'mode1') into another mode (of type 'mode2'), doing some user
-- interactions, and returning back to the first mode with a value of
-- type 'a' using the supplied continuation.
type ThroughMode origin mode m n a
   = forall r1 r2 r3 state2 state1 b.
   ( UserInterface m
     , HasType n state1 r1
     , HasType n state1 r3
     , Modify n state2 r1 ~ r2
     , HasType n state2 r2
     , Modify n state1 r2 ~ r3
     , Modify n state2 r2 ~ r2
     , state1 ~ State m origin
     , state2 ~ State m mode
     )
   => (a -> m r2 r3 b)
   -> m r1 r3 b
