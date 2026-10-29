#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$testRoot=Join-Path $root ('.testdata\native-policy-'+[guid]::NewGuid().ToString('N'))
$appRoot=Join-Path $testRoot 'app'
[void][IO.Directory]::CreateDirectory($appRoot)
$source=[IO.File]::ReadAllText((Join-Path $root 'app\DaiBan.ps1'))
$tracking=[IO.File]::ReadAllText((Join-Path $root 'app\Tracking.ps1'))
$script=$source.Replace(". (Join-Path `$script:AppRoot 'Tracking.ps1')",$tracking)
$hostSource=[IO.File]::ReadAllText((Join-Path $root 'host\DaiBanHost.cs'))
if(-not $hostSource.Contains('return script.Replace(loader, ReadResourceText("DaiBan.Tracking.ps1"));')){throw 'Host must use the same embedded composition'}
if($script.Contains(". (Join-Path `$script:AppRoot 'Tracking.ps1')")){throw 'External script loader still present'}
foreach($relative in @('ui.xaml','themes\light.xaml','themes\dark.xaml','app.ico')){
    $destination=Join-Path $appRoot $relative
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $destination))
    [IO.File]::Copy((Join-Path (Join-Path $root 'app') $relative),$destination)
}
[IO.File]::Copy((Join-Path $root 'LICENSE'),(Join-Path $appRoot 'LICENSE'))
$env:DAIBAN_APP_ROOT=$appRoot
$env:DAIBAN_DATA_DIR=Join-Path $testRoot 'data'
$env:DAIBAN_CONFIG_DIR=Join-Path $testRoot 'config'
$automation=@'
$script:Window.Show()
if (Get-ExecutionPolicy -ne 'Restricted') { throw 'Test policy is not Restricted' }
if (-not (Get-Command Get-OrderedTasks -ErrorAction SilentlyContinue)) { throw 'Embedded tracking functions not loaded' }
$script:NewTaskInput.Text='Native policy test'
Add-TaskFromComposer
$script:TimingFeatureToggle.IsChecked=$true
Start-TaskTimer $script:ActiveTasks[0]
Stop-TaskTimer
$script:StatisticsFeatureToggle.IsChecked=$true
$script:FilterStats.IsChecked=$true
if($script:StatsError.Text){throw $script:StatsError.Text}
if(-not $script:LastTasksSaveSucceeded){throw 'Native task save failed'}
$script:Window.Close()
'@
$script=$script.Replace('[void]$script:Application.Run($script:Window)',$automation)
$initial=[Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
$initial.ExecutionPolicy=[Microsoft.PowerShell.ExecutionPolicy]::Restricted
$runspace=[Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($initial)
$runspace.ApartmentState='STA';$runspace.Open()
$ps=[Management.Automation.PowerShell]::Create();$ps.Runspace=$runspace
try{
    [void]$ps.AddScript($script);[void]$ps.Invoke()
    if($ps.Streams.Error.Count){throw ($ps.Streams.Error|Out-String)}
    if(Test-Path (Join-Path $appRoot 'Tracking.ps1')){throw 'External tracking file should not exist'}
    Write-Host 'Native embedded script starts, saves tasks and initializes timing/statistics under Restricted policy without external .ps1 files.'
}finally{$ps.Dispose();$runspace.Dispose()}
