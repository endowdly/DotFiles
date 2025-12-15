@{
    Error = @{
        AddEntry = 'FriendId {0} already exists in the manifest and could not be added'
    }
    NounPlural       = 's'
    ToBePlural       = 'are'
    ToBeSingle       = 'is'
    TerminatingError = @{
        RealBadPath    = '{0} is an invalid path and cannot be written to!'
        BadConfig      = '''{0}'' {1} not a valid config key{2}. Valid key{3} {4}: {5}'
        BadPath        = '{0} is a bad path and does not exist or is inaccessible'
        ConfigNotFound = 'Fatal: config file ''{0}'' not found or invalid!'
        What           = 'Fatal: you somehow reached the unreachable!'
        Wip            = 'Work in progress: Not implemented yet!'
        NotAManifest   = '''{0}'' is not a valid manifest file!'
    }
    ShouldProcess    = @{
        ExportDotFile = 'Overwrite dotfiles manifest'
        UpdateManifest = 'Update dotfiles manifest from target'
        AddManifestEntry = 'Adding Entry with FriendId {0} for target'
    }
    ShouldContinue   = @{
        SyncDotFiles      = @{
            Query   = 'There {0} {1} file{2} to push and {3} file{4} to pull. Sync?'
            Caption = 'Sync Dot Files'
        }
        UpdateDotFiles    = @{
            Query   = 'This will push and overwrite {0} files to the dotfiles archive from the local computer. Continue?'
            Caption = 'Update DotFiles Archive'
        } 
        UpdateLocalFiles  = @{
            Query   = 'This will pull and overwrite {0} files from the dotfiles archive to local computer. Continue?'
            Caption = 'Update Local Files with DotFiles Archive'
        }
        SaveDotCommands   = @{
            Query   = 'Save {0} commands data to the dotfiles archive?'
            Caption = 'Save entry commands from current manifest'
        }
        InvokeDotCommands = @{
            Query   = 'Run {0} commands? Some may use data in the archive.'
            Caption = 'Invoke dot commands'
        }
    }      
       
    Choice           = @{
        Common               = @{
            Exit   = 'E&xit'

        }
        InvokeDotFileSync    = @{
            Sync = '&Sync'
            Pull = 'Pu&ll'
            Push = 'Pus&h'
        }
        InvokeDotCommandSync = @{
            Save   = '&Save'
            Invoke = '&Invoke'
        }
    }
    HelpMessage      = @{
        Common               = @{
            Exit   = 'Does nothing and quits the cmdlet'
        }
        InvokeDotFileSync    = @{
            Sync = 'Push newer local files and pull newer dot files'
            Pull = 'Pull dot files and overwrite local files'
            Push = 'Push local files and overwrite dot files'
        }
        InvokeDotCommandSync = @{
            Save   = 'Saves the output of the commands in the manifest file'
            Invoke = 'Invokes the commands with the data in the archive, if any'
        }
    }

    PromptForChoice  = @{
        InvokeDotFileSync    = @{
            ChoiceCaption = 'How do you want to sync?'
            ChoiceMessage = 'File Sync'
        }
        InvokeDotCommandSync = @{
            ChoiceCaption = 'How do you want to sync?'
            ChoiceMessage = 'Command Sync'
        }
    } 

    Warning          = @{
        ConfigFileNotFound = 'No configuration file found. Using default configuration.'
        NoManifestFile     = 'No manifest file found at {0}. Run `Initialize-DotFilesManifest`.'
    }
}

