@{  
    GUID = "{B9AF2675-4726-42FD-ADAB-38228176A516}"  
    Author = "Microsoft Corporation"  
    CLRVersion = "4.0"  
    CompanyName = "Microsoft Corporation"  
    Copyright = "(c) Microsoft Corporation. All rights reserved."  
    AliasesToExport = @()  
    FunctionsToExport = "Disable-DeliveryOptimizationVerboseLogs",
                        "Enable-DeliveryOptimizationVerboseLogs",
                        "Get-DeliveryOptimizationStatus",
                        "Get-DeliveryOptimizationPerfSnap",
                        "Get-DeliveryOptimizationPerfSnapThisMonth",
                        "Get-DOConfig",
                        "Get-DODownloadMode",
                        "Get-DOPercentageMaxForegroundBandwidth",
                        "Get-DOPercentageMaxBackgroundBandwidth"
    CmdletsToExport = "Delete-DeliveryOptimizationCache",
                      "Set-DeliveryOptimizationStatus",
                      "Get-DeliveryOptimizationLog",
                      "Get-DeliveryOptimizationLogAnalysis",
                      "Set-DODownloadMode", 
                      "Set-DOPercentageMaxForegroundBandwidth", 
                      "Set-DOPercentageMaxBackgroundBandwidth"
    PowerShellVersion = '5.1'
    ModuleVersion = "1.0.2.0"
    NestedModules = @('Microsoft.Windows.DeliveryOptimization.AdminCommands', 'DeliveryOptimizationVerboseLogs.psm1', 'DeliveryOptimizationStatus.psm1')
    CompatiblePSEditions = @('Core','Desktop')
}
