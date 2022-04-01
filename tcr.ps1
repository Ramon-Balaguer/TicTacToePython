# SETUP
$commandToBuild = "python -m compileall"
$commandToTest = "python -m unittest"
$commitMsg = "tcr success"
$folderToWatch = "."
$extensionsToWatch = "*.*"

Function Build-Failed{
    Write-Host "### Building the solution" -ForegroundColor Blue
    Invoke-Command $commandToBuild
    return $LASTEXITCODE -eq 1
}

function Tests-Pass{
    Write-Host "### Running tests" -ForegroundColor Blue
    Invoke-Command $commandToTest
    return $LASTEXITCODE -eq 0
}

Function Commit{
    Invoke-Command "git add --all"
    Invoke-Command "git commit -m '$commitMsg'"
    Invoke-Command "git pull --rebase"
    Invoke-Command "git push"
}

Function Revert{
    Invoke-Command "git checkout HEAD -- $folderToWatch"
    if($LASTEXITCODE -ne 0){
        Write-Host "Unable to revert. Git's broke somewhere. [LASTEXITCODE=$LASTEXITCODE]" -ForegroundColor Red
    }
}

Function Invoke-Command($command){
    Write-Host "Executing [$command]" -ForegroundColor Yellow
    Invoke-Expression -Command: $command | Write-Host
}

$global:debounceTime = (Get-Date)

Function global:Debounce($time){
    if($global:debounceTime -ge $time){
        return $true
    }
    $global:debounceTime = $time
    return $false
}

Function global:EndRunSet($time){
    $global:debounceTime = $time
}

Function global:TCR($event){
    if(Debounce($event.TimeGenerated)){
        return
    }

    try{
        Write-Host "### Starting TCR" -ForegroundColor Blue

        if(Build-Failed){ 
            Write-Host "### Build failed. No change." -ForegroundColor Magenta
			Revert
            return
        }

        Write-Host "### Build Passed"  -ForegroundColor Blue

        if(Tests-Pass){ 
            Write-Host "### Tests Passed. Commiting Changes."  -ForegroundColor Green
            Commit
            return
        } 

        #Default behavior is to revert.
        Write-Host "### Tests Failed. Reverting..." -ForegroundColor Red
        Revert

    }
    finally{
        Write-Host "### Ending TCR" -ForegroundColor Blue
        EndRunSet(Get-Date)
    }
}


Function Register-Watcher {
    $folder = "$(Get-Location)\$folderToWatch"
    Write-Host "Watching $folder"
    $watcher = New-Object IO.FileSystemWatcher $folder, $extensionsToWatch -Property @{ 
        IncludeSubdirectories = $true
        EnableRaisingEvents = $true 
    }

    return $watcher
}

Function StartTCR{
    $FileSystemWatcher = Register-Watcher
    $Action = {TCR $event}
    $handlers = . {
        Register-ObjectEvent -InputObject $FileSystemWatcher -EventName "Changed" -Action $Action -SourceIdentifier FSChange
        Register-ObjectEvent -InputObject $FileSystemWatcher -EventName "Created" -Action $Action -SourceIdentifier FSCreate
        Register-ObjectEvent -InputObject $FileSystemWatcher -EventName "Deleted" -Action $Action -SourceIdentifier FSDelete
        Register-ObjectEvent -InputObject $FileSystemWatcher -EventName "Renamed" -Action $Action -SourceIdentifier FSRename
    }

    try
    {
        do
        {
            Wait-Event -Timeout 1
            Write-Host "." -NoNewline
            
        } while ($true)
    }
    finally
    {
        Write-Host "Exiting..."
        Unregister-Event -SourceIdentifier FSChange
        Unregister-Event -SourceIdentifier FSCreate
        Unregister-Event -SourceIdentifier FSDelete
        Unregister-Event -SourceIdentifier FSRename
        $handlers | Remove-Job
        $FileSystemWatcher.EnableRaisingEvents = $false
        $FileSystemWatcher.Dispose()
        "Event Handler disabled."
    }
}


StartTCR