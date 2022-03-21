[CmdletBinding(DefaultParameterSetName="Default")]
param ( [Parameter(Mandatory=$true,ParameterSetName="file")]$file, [Parameter(ParameterSetName="file")][switch]$Generate, [Parameter(ParameterSetName="file")][switch]$force )
if ( ! $IsWindows ) {
    throw "this can only be run on Windows"
}
$exe = "netsh.exe"
$helpChar = "-?"
$commandPattern = "Commands in this context:$"
$optionPattern = "options are available:"
$usagePattern = "^Usage: (?<usage>.*)"
$argumentPattern = "arguments are available:"
$headerLength = 0
$linkPattern = "^More help can be found at: (?<link>.*)"
$parmPattern = "--(?<pname>\w+)\s+(?<phelp>.*)"

class ParsedCommand {
    [string]$exe
    [string[]]$commandElements
    [string]$Verb
    [string]$Noun
    [cParameter[]]$Parameters
    [string]$Usage
    [string[]]$Help
    [string]$Link
    [string[]]$OriginalHelptext
    [object]GetCrescendoCommand() {
        $c = New-CrescendoCommand -Verb $this.Verb -Noun $this.Noun -originalname $this.exe
        if ( $this.Usage ) {
            $c.Usage = New-UsageInfo -usage $this.Usage
        }
        else {
            Write-Verbose ("skipping usage for " + ($this.commandElements -join " "))
        }
        if ( $this.CommandElements ) {
            $c.OriginalCommandElements = $this.commandElements | foreach-object {$_}
        }
        $c.Platform = "Windows"
        $c.OriginalText = $this.OriginalHelptext -join ([char]5)
        $c.Description = $this.Help -join "`n"
        $c.HelpLinks = $this.Link
        foreach ( $p in $this.Parameters) {
            $parm = New-ParameterInfo -name $p.Name -originalName $p.OriginalName
            $parm.Description = $p.Help
            if ( $p.Position -ne [int]::MaxValue ) {
                $parm.Position = $p.Position
            }
            $c.Parameters.Add($parm)
        }
        return $c
    }
    [string]GetCrescendoJson() {
        return $this.GetCrescendoCommand().GetCrescendoConfiguration()
    }
}

class cParameter {
    [string]$Name
    [string]$OriginalName
    [string]$Help
    [int]$Position = [int]::MaxValue
    cParameter([string]$name, [string]$originalName, [string]$help) {
        $this.Name = $name
        $this.OriginalName = $originalName
        $this.Help = $help
    }
}

function Get-Parm ( $parameterString ) {
    write-verbose $parameterString
}

function Test-ParameterContinue {
    param ( [string[]]$text, [int]$offset )
    [bool]$continues = $false
    if ($offset -ge $text.Count ) {
        break
    }
    elseif ( $text[$i+1] -match "^\s{9}(?<parm>[^\s].*)" ) {
        $continues = $true
    }
    elseif ( $text[$i+1] -match "^\s{13}[^\s]" ) {
        $continues = $true
    }
    elseif ( $text[$i].Trim() -match "\|$" ) {
        $continues = $true
    }
    elseif ( $text[$i+1].Trim() -match "^\|" ) {
        $continues = $true
    }
    return $continues
}

function Test-IsParameter {
    param ( [string[]]$text, [int]$offset )
    if ( $offset -ge $text.Count ) {
        return $false
    }
    [string]$possibleParameter = $text[$offset].Trim()
    if ( $possibleParameter -eq "Not Supported." ) {
        return $false
    }
    elseif ( $possibleParameter -eq "Please go to the Network Connections folder to install." ){
        return $false
    }
    elseif ( $text[$offset] -match "^\s{6}(?<parm>[^\s].*)" ) {
        return $true
    }
    return $false
}

function Get-ParameterFromUsage ( [string[]]$prolog, [string]$usage ) {

    #wait-debugger
    $pnum = $prolog.count - 1
    if ( $pnum -ge 0 ) {
        foreach ( $i in 0..$pnum ) {
            $plog = $prolog[${i}..($pnum)] -join " "
            if ( $usage -match "$plog" ) {
                $parm = $usage -replace ".*${plog}"
                $parm = "$parm".Trim()
                # if ( $parm -match " " ) { wait-debugger  }
                if ( "$parm" -eq "" ){ Write-Verbose ("trimmed everything from $usage with " + ($prolog -join ":"))}
                return "$parm"
            }
        }
    }
    if ( $usage -match ".*${exe} (?<parms>.*)" ) {
        $parm = $matches['parms'].Trim()
        # if ( $parm -match " " ) { wait-debugger  }
        return $parm
    }
    # wait-debugger
    Write-verbose "no parameter in $usage"
    return "no parameter"
}

function parseHelp([string]$exe, [string[]]$commandProlog) {
    write-progress ("parsing help for '$exe " + ($commandProlog -join " ") + "'")
    if ( $commandProlog ) {
        $helpText = & $exe $commandProlog $helpChar
    }
    else {
        $helpText = & $exe $helpChar
    }
    $offset = $headerLength
    $cmdhelp = @()
    while ( $helpText[$offset] -ne "" -and $offset -lt $helpText.Count) {
        $cmdhelp += $helpText[$offset++]
    }
    #$cmdHelpString = $cmdhelp -join " "
    $parameters = @()
    $usage = ""
    for($i = $offset; $i -lt $helpText.Count; $i++) {
        if ($helpText[$i] -match $usagePattern) {
            $usage = $matches['usage']
            try {
                $pp = get-parameterfromusage -prolog $commandprolog -usage $usage
                if ( $pp ) {
                    $parameters += $pp
                }
            }
            catch {
                wait-debugger
            }
            continue
            # this mess is about finding parameters - skip for now
            while ( Test-ParameterContinue -text $helpText -offset $i ) {
                $i++
                $usage += $helpText[$i].Trim()
                #wait-debugger
            }
            # manage parameters here
            $i++
            while($i -lt $helpText.Count -and $helpText[$i][0] -eq " ") {
                if (Test-IsParameter -text $helpText -offset $i) {
                    $helptext[$offset] -match "\s{6}(?<parm>[^\s].*)"
                    try {
                        $p = $matches['parm'].Trim()
                    }
                    catch {
                        wait-debugger
                    }

                    while ( Test-ParameterContinue -text $helpText -offset $i ) {
                        $i++
                        $p += $helpText[$i].Trim()
                        #wait-debugger
                    }
                    if ( $p -match "not supported" ) { wait-debugger }
                    if ( ! "$p".Trim() ) { wait-debugger }
                    Get-Parm -parameterString $p
                    $parameters += $p
                    $p = ""
                    if( $matches ) {
                        $matches.Clear()
                    }
                }
                $i++
            }
        }
        elseif ($helpText[$i] -match $linkPattern ) {
            $link = $matches['link']
        }
        elseif ($helpText[$i] -match $optionPattern) {
            $i++
            while($helpText[$i] -ne "") {
                if ($helpText[$i] -match $parmPattern) {
                    $originalName = "--" + $matches['pname']
                    $pHelp = $matches['phelp']
                    $pName = $originalName -replace "[- ]"
                    $p = [cParameter]::new($pName, $originalName, $pHelp)
                    $parameters += $p
                }
                $i++
            }
        }
        elseif ($helpText[$i] -match $argumentPattern) {
            $i++
            $position = 0
            while($helpText[$i] -ne "") {
                if ($helpText[$i] -match $parmPattern -and $i -lt $helpText.Count) {
                    $originalName = "--" + $matches['pname']
                    $pHelp = $matches['phelp']
                    $pName = $originalName -replace "[- ]"
                    $p = [cParameter]::new($pName, $originalName, $pHelp)
                    $p.Position = $position++
                    $parameters += $p
                }
                $i++
            }
        }
        elseif ($helpText[$i] -match $commandPattern) {
            $i++
            $subCommands = @()
            while($helpText[$i] -ne "" -and $i -le $helpText.Count) {
                try {
                    $t = $helpText[$i].Trim()
                }
                catch {
                    break
                }
                $subCommands, $subHelp = $t.split("-", 2, [System.StringSplitOptions]::RemoveEmptyEntries)
                $subcommand = $subCommands.Trim().Split(" ",[System.StringSplitOptions]::RemoveEmptyEntries)[-1]
                if ( $helpText[$i+1] -and $helpText[$i+1][0] -eq " " ) {
                    $i++
                    while($helpText[$i+1] -and $helpText[$i][0] -eq " " -and $i -lt $helpText.Count) {
                        $subHelp += " " + $helpText[$i].Trim()
                        $i++
                    }
                }
                #$subCommand, $dash, $subHelp = $t.split(" ",3, [System.StringSplitOptions]::RemoveEmptyEntries)
                # skip '?' and 'help'
                if ( $subCommand -eq "?" -or $subCommand -eq "help") {
                    $i++
                    continue
                }
                $cPro = $commandProlog
                $cPro += $subCommand
                #if ( $cPro[0] -eq "firewall" -and $cPro[1] -eq "add") {
                #    wait-debugger
                #}
                #write-host (">>> " + ($cPro -join " "))
                parseHelp -exe $exe -commandProlog $cPro
                $i++
            }
        }
    }
    $c = [Parsedcommand]::new()
    $c.exe = $exe
    $c.commandElements = $commandProlog
    $c.Verb = "Invoke"
    $c.Noun = $("$exe" -replace ".exe";$commandProlog).Foreach({"$_".split("-")}).Foreach({[char]::ToUpper("$_"[0]) + "$_".SubString(1).toLower()}) -join ""
    # $c.Parameters = $parameters
    $c.Usage = $usage
    $c.Help = $cmdhelp
    $c.Link = $link
    $c.OriginalHelptext = $helpText
    $c
}

$commands = parseHelp -exe $exe -commandProlog @()
$trimmedCommands = $commands.Where({$_.Usage -or ($_.commandElements -contains "show" -and $_.commandElements[-1] -ne "show")})
$convertedCommands = $trimmedCommands | ForEach-Object { $_.GetCrescendoCommand()}

$h = [ordered]@{
    '$schema' = 'https://aka.ms/PowerShell/Crescendo/Schemas/2021-11'
    'Commands' = $convertedCommands
}

if ( ! $Generate ) {
    $h
    return
}

$sOptions = [System.Text.Json.JsonSerializerOptions]::new()
$sOptions.WriteIndented = $true
$sOptions.MaxDepth = 20
$sOptions.IgnoreNullValues = $true

$ParsedConfig = [System.Text.Json.JsonSerializer]::Serialize($h, $sOptions)

if ( $file ) {
    if (test-path $file) {
        if ($force) {
            $parsedConfig > $file
        }
        else {
            Write-Error "'$file' exists, use '-force' to overwrite"
        }
    }
    else {
        $parsedConfig > $file
    }
}
else {
    $parsedConfig
}

# SIG # Begin signature block
# MIInngYJKoZIhvcNAQcCoIInjzCCJ4sCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAxNHxcf2ondI6B
# sA7fktHJzUzZ41Os4yyB2Aor/p1UHqCCDYEwggX/MIID56ADAgECAhMzAAACUosz
# qviV8znbAAAAAAJSMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjEwOTAyMTgzMjU5WhcNMjIwOTAxMTgzMjU5WjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQDQ5M+Ps/X7BNuv5B/0I6uoDwj0NJOo1KrVQqO7ggRXccklyTrWL4xMShjIou2I
# sbYnF67wXzVAq5Om4oe+LfzSDOzjcb6ms00gBo0OQaqwQ1BijyJ7NvDf80I1fW9O
# L76Kt0Wpc2zrGhzcHdb7upPrvxvSNNUvxK3sgw7YTt31410vpEp8yfBEl/hd8ZzA
# v47DCgJ5j1zm295s1RVZHNp6MoiQFVOECm4AwK2l28i+YER1JO4IplTH44uvzX9o
# RnJHaMvWzZEpozPy4jNO2DDqbcNs4zh7AWMhE1PWFVA+CHI/En5nASvCvLmuR/t8
# q4bc8XR8QIZJQSp+2U6m2ldNAgMBAAGjggF+MIIBejAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQUNZJaEUGL2Guwt7ZOAu4efEYXedEw
# UAYDVR0RBEkwR6RFMEMxKTAnBgNVBAsTIE1pY3Jvc29mdCBPcGVyYXRpb25zIFB1
# ZXJ0byBSaWNvMRYwFAYDVQQFEw0yMzAwMTIrNDY3NTk3MB8GA1UdIwQYMBaAFEhu
# ZOVQBdOCqhc3NyK1bajKdQKVMFQGA1UdHwRNMEswSaBHoEWGQ2h0dHA6Ly93d3cu
# bWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY0NvZFNpZ1BDQTIwMTFfMjAxMS0w
# Ny0wOC5jcmwwYQYIKwYBBQUHAQEEVTBTMFEGCCsGAQUFBzAChkVodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY0NvZFNpZ1BDQTIwMTFfMjAx
# MS0wNy0wOC5jcnQwDAYDVR0TAQH/BAIwADANBgkqhkiG9w0BAQsFAAOCAgEAFkk3
# uSxkTEBh1NtAl7BivIEsAWdgX1qZ+EdZMYbQKasY6IhSLXRMxF1B3OKdR9K/kccp
# kvNcGl8D7YyYS4mhCUMBR+VLrg3f8PUj38A9V5aiY2/Jok7WZFOAmjPRNNGnyeg7
# l0lTiThFqE+2aOs6+heegqAdelGgNJKRHLWRuhGKuLIw5lkgx9Ky+QvZrn/Ddi8u
# TIgWKp+MGG8xY6PBvvjgt9jQShlnPrZ3UY8Bvwy6rynhXBaV0V0TTL0gEx7eh/K1
# o8Miaru6s/7FyqOLeUS4vTHh9TgBL5DtxCYurXbSBVtL1Fj44+Od/6cmC9mmvrti
# yG709Y3Rd3YdJj2f3GJq7Y7KdWq0QYhatKhBeg4fxjhg0yut2g6aM1mxjNPrE48z
# 6HWCNGu9gMK5ZudldRw4a45Z06Aoktof0CqOyTErvq0YjoE4Xpa0+87T/PVUXNqf
# 7Y+qSU7+9LtLQuMYR4w3cSPjuNusvLf9gBnch5RqM7kaDtYWDgLyB42EfsxeMqwK
# WwA+TVi0HrWRqfSx2olbE56hJcEkMjOSKz3sRuupFCX3UroyYf52L+2iVTrda8XW
# esPG62Mnn3T8AuLfzeJFuAbfOSERx7IFZO92UPoXE1uEjL5skl1yTZB3MubgOA4F
# 8KoRNhviFAEST+nG8c8uIsbZeb08SeYQMqjVEmkwggd6MIIFYqADAgECAgphDpDS
# AAAAAAADMA0GCSqGSIb3DQEBCwUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUm9vdCBDZXJ0aWZpY2F0
# ZSBBdXRob3JpdHkgMjAxMTAeFw0xMTA3MDgyMDU5MDlaFw0yNjA3MDgyMTA5MDla
# MH4xCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMT
# H01pY3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTEwggIiMA0GCSqGSIb3DQEB
# AQUAA4ICDwAwggIKAoICAQCr8PpyEBwurdhuqoIQTTS68rZYIZ9CGypr6VpQqrgG
# OBoESbp/wwwe3TdrxhLYC/A4wpkGsMg51QEUMULTiQ15ZId+lGAkbK+eSZzpaF7S
# 35tTsgosw6/ZqSuuegmv15ZZymAaBelmdugyUiYSL+erCFDPs0S3XdjELgN1q2jz
# y23zOlyhFvRGuuA4ZKxuZDV4pqBjDy3TQJP4494HDdVceaVJKecNvqATd76UPe/7
# 4ytaEB9NViiienLgEjq3SV7Y7e1DkYPZe7J7hhvZPrGMXeiJT4Qa8qEvWeSQOy2u
# M1jFtz7+MtOzAz2xsq+SOH7SnYAs9U5WkSE1JcM5bmR/U7qcD60ZI4TL9LoDho33
# X/DQUr+MlIe8wCF0JV8YKLbMJyg4JZg5SjbPfLGSrhwjp6lm7GEfauEoSZ1fiOIl
# XdMhSz5SxLVXPyQD8NF6Wy/VI+NwXQ9RRnez+ADhvKwCgl/bwBWzvRvUVUvnOaEP
# 6SNJvBi4RHxF5MHDcnrgcuck379GmcXvwhxX24ON7E1JMKerjt/sW5+v/N2wZuLB
# l4F77dbtS+dJKacTKKanfWeA5opieF+yL4TXV5xcv3coKPHtbcMojyyPQDdPweGF
# RInECUzF1KVDL3SV9274eCBYLBNdYJWaPk8zhNqwiBfenk70lrC8RqBsmNLg1oiM
# CwIDAQABo4IB7TCCAekwEAYJKwYBBAGCNxUBBAMCAQAwHQYDVR0OBBYEFEhuZOVQ
# BdOCqhc3NyK1bajKdQKVMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMAsGA1Ud
# DwQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB8GA1UdIwQYMBaAFHItOgIxkEO5FAVO
# 4eqnxzHRI4k0MFoGA1UdHwRTMFEwT6BNoEuGSWh0dHA6Ly9jcmwubWljcm9zb2Z0
# LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY1Jvb0NlckF1dDIwMTFfMjAxMV8wM18y
# Mi5jcmwwXgYIKwYBBQUHAQEEUjBQME4GCCsGAQUFBzAChkJodHRwOi8vd3d3Lm1p
# Y3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1Jvb0NlckF1dDIwMTFfMjAxMV8wM18y
# Mi5jcnQwgZ8GA1UdIASBlzCBlDCBkQYJKwYBBAGCNy4DMIGDMD8GCCsGAQUFBwIB
# FjNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2RvY3MvcHJpbWFyeWNw
# cy5odG0wQAYIKwYBBQUHAgIwNB4yIB0ATABlAGcAYQBsAF8AcABvAGwAaQBjAHkA
# XwBzAHQAYQB0AGUAbQBlAG4AdAAuIB0wDQYJKoZIhvcNAQELBQADggIBAGfyhqWY
# 4FR5Gi7T2HRnIpsLlhHhY5KZQpZ90nkMkMFlXy4sPvjDctFtg/6+P+gKyju/R6mj
# 82nbY78iNaWXXWWEkH2LRlBV2AySfNIaSxzzPEKLUtCw/WvjPgcuKZvmPRul1LUd
# d5Q54ulkyUQ9eHoj8xN9ppB0g430yyYCRirCihC7pKkFDJvtaPpoLpWgKj8qa1hJ
# Yx8JaW5amJbkg/TAj/NGK978O9C9Ne9uJa7lryft0N3zDq+ZKJeYTQ49C/IIidYf
# wzIY4vDFLc5bnrRJOQrGCsLGra7lstnbFYhRRVg4MnEnGn+x9Cf43iw6IGmYslmJ
# aG5vp7d0w0AFBqYBKig+gj8TTWYLwLNN9eGPfxxvFX1Fp3blQCplo8NdUmKGwx1j
# NpeG39rz+PIWoZon4c2ll9DuXWNB41sHnIc+BncG0QaxdR8UvmFhtfDcxhsEvt9B
# xw4o7t5lL+yX9qFcltgA1qFGvVnzl6UJS0gQmYAf0AApxbGbpT9Fdx41xtKiop96
# eiL6SJUfq/tHI4D1nvi/a7dLl+LrdXga7Oo3mXkYS//WsyNodeav+vyL6wuA6mk7
# r/ww7QRMjt/fdW1jkT3RnVZOT7+AVyKheBEyIXrvQQqxP/uozKRdwaGIm1dxVk5I
# RcBCyZt2WwqASGv9eZ/BvW1taslScxMNelDNMYIZczCCGW8CAQEwgZUwfjELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEoMCYGA1UEAxMfTWljcm9z
# b2Z0IENvZGUgU2lnbmluZyBQQ0EgMjAxMQITMwAAAlKLM6r4lfM52wAAAAACUjAN
# BglghkgBZQMEAgEFAKCBrjAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgor
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgpyJ+wE6v
# wfhZb1+v7idugiXIOLQ8g0xR5vaN5u/r9n4wQgYKKwYBBAGCNwIBDDE0MDKgFIAS
# AE0AaQBjAHIAbwBzAG8AZgB0oRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
# BgkqhkiG9w0BAQEFAASCAQB2VMfcALzvVuzeM6gVD8QVnZbx2PA54vs81K7aJJc1
# UZaOLXaYLFWVYXiPmxXzw0G0Jdxzv+twJvT6/hWUlLpfzQgLqadr0+0jagkUW3rR
# qK78Kx4C29qp+OoEdgnLXBanzYWNdWZg8hv1EAwuNmlD/oEVghszXGrGnL9+YKc3
# 8szj2obQ74JADN3lG1Q47BKB1BhR3zw7uvBXq0gLcgH/e7gXR2sEDlZ8hgP02eCw
# tRRcS03Ni8YIgvH2vHa5hCTlCf5QqygwMCt3hJ9TFSFtNL82u4CXkalKj35Z58ez
# CwOJkUl3mJJZbR968hprB/M8EYUU6lzsqTx7ELGHqhq2oYIW/TCCFvkGCisGAQQB
# gjcDAwExghbpMIIW5QYJKoZIhvcNAQcCoIIW1jCCFtICAQMxDzANBglghkgBZQME
# AgEFADCCAVEGCyqGSIb3DQEJEAEEoIIBQASCATwwggE4AgEBBgorBgEEAYRZCgMB
# MDEwDQYJYIZIAWUDBAIBBQAEIHccQkUjTbXezcnZ/W84AgTLij+d9VX2gLU7ppwO
# 6mjwAgZiFmytvFoYEzIwMjIwMzAyMjM0MTI0LjA5MlowBIACAfSggdCkgc0wgcox
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJTAjBgNVBAsTHE1p
# Y3Jvc29mdCBBbWVyaWNhIE9wZXJhdGlvbnMxJjAkBgNVBAsTHVRoYWxlcyBUU1Mg
# RVNOOjEyQkMtRTNBRS03NEVCMSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFt
# cCBTZXJ2aWNloIIRVDCCBwwwggT0oAMCAQICEzMAAAGhAYVVmblUXYoAAQAAAaEw
# DQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwHhcN
# MjExMjAyMTkwNTI0WhcNMjMwMjI4MTkwNTI0WjCByjELMAkGA1UEBhMCVVMxEzAR
# BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
# Y3Jvc29mdCBDb3Jwb3JhdGlvbjElMCMGA1UECxMcTWljcm9zb2Z0IEFtZXJpY2Eg
# T3BlcmF0aW9uczEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046MTJCQy1FM0FFLTc0
# RUIxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0G
# CSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDayTxe5WukkrYxxVuHLYW9BEWCD9kk
# jnnHsOKwGddIPbZlLY+l5ovLDNf+BEMQKAZQI3DX91l1yCDuP9X7tOPC48ZRGXA/
# bf9ql0FK5438gIl7cV528XeEOFwc/A+UbIUfW296Omg8Z62xaQv3jrG4U/priArF
# /er1UA1HNuIGUyqjlygiSPwK2NnFApi1JD+Uef5c47kh7pW1Kj7RnchpFeY9MekP
# QRia7cEaUYU4sqCiJVdDJpefLvPT9EdthlQx75ldx+AwZf2a9T7uQRSBh8tpxPdI
# DDkKiWMwjKTrAY09A3I/jidqPuc8PvX+sqxqyZEN2h4GA0Edjmk64nkIukAK18K5
# nALDLO9SMTxpAwQIHRDtZeTClvAPCEoy1vtPD7f+eqHqStuu+XCkfRjXEpX9+h9f
# rsB0/BgD5CBf3ELLAa8TefMfHZWEJRTPNrbXMKizSrUSkVv/3HP/ZsJpwaz5My2R
# byc3Ah9bT76eBJkyfT5FN9v/KQ0HnxhRMs6HHhTmNx+LztYci+vHf0D3QH1eCjZW
# ZRjp1mOyxpPU2mDMG6gelvJse1JzRADo7YIok/J3Ccbm8MbBbm85iogFltFHecHF
# EFwrsDGBFnNYHMhcbarQNA+gY2e2l9fAkX3MjI7Uklkoz74/P6KIqe5jcd9FPCbb
# SbYH9OLsteeYOQIDAQABo4IBNjCCATIwHQYDVR0OBBYEFBa/IDLbY475VQyKiZSw
# 47l0/cypMB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRY
# MFYwVKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01p
# Y3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEF
# BQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9w
# a2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAo
# MSkuY3J0MAwGA1UdEwEB/wQCMAAwEwYDVR0lBAwwCgYIKwYBBQUHAwgwDQYJKoZI
# hvcNAQELBQADggIBACDDIxElfXlG5YKcKrLPSS+f3JWZprwKEiASvivaHTBRlXtA
# s+TkadcsEei+9w5vmF5tCUzTH4c0nCI7bZxnsL+S6XsiOs3Z1V4WX+IwoXUJ4zLv
# s0+mT4vjGDtYfKQ/bsmJKar2c99m/fHv1Wm2CTcyaePvi86Jh3UyLjdRILWbtzs4
# oImFMwwKbzHdPopxrBhgi+C1YZshosWLlgzyuxjUl+qNg1m52MJmf11loI7D9HJo
# aQzd+rf928Y8rvULmg2h/G50o+D0UJ1Fa/cJJaHfB3sfKw9X6GrtXYGjmM3+g+Ah
# aVsfupKXNtOFu5tnLKvAH5OIjEDYV1YKmlXuBuhbYassygPFMmNgG2Ank3drEcDc
# ZhCXXqpRszNo1F6Gu5JCpQZXbOJM9Ue5PlJKtmImAYIGsw+pnHy/r5ggSYOp4g5Z
# 1oU9GhVCM3V0T9adee6OUXBk1rE4dZc/UsPlj0qoiljL+lN1A5gkmmz7k5tIObVG
# B7dJdz8J0FwXRE5qYu1AdvauVbZwGQkL1x8aK/svjEQW0NUyJ29znDHiXl5vLoRT
# jjFpshUBi2+IY+mNqbLmj24j5eT+bjDlE3HmNtLPpLcMDYqZ1H+6U6YmaiNmac2j
# RXDAaeEE/uoDMt2dArfJP7M+MDv3zzNNTINeuNEtDVgm9zwfgIUCXnDZuVtiMIIH
# cTCCBVmgAwIBAgITMwAAABXF52ueAptJmQAAAAAAFTANBgkqhkiG9w0BAQsFADCB
# iDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMp
# TWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5IDIwMTAwHhcNMjEw
# OTMwMTgyMjI1WhcNMzAwOTMwMTgzMjI1WjB8MQswCQYDVQQGEwJVUzETMBEGA1UE
# CBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9z
# b2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQ
# Q0EgMjAxMDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAOThpkzntHIh
# C3miy9ckeb0O1YLT/e6cBwfSqWxOdcjKNVf2AX9sSuDivbk+F2Az/1xPx2b3lVNx
# WuJ+Slr+uDZnhUYjDLWNE893MsAQGOhgfWpSg0S3po5GawcU88V29YZQ3MFEyHFc
# UTE3oAo4bo3t1w/YJlN8OWECesSq/XJprx2rrPY2vjUmZNqYO7oaezOtgFt+jBAc
# nVL+tuhiJdxqD89d9P6OU8/W7IVWTe/dvI2k45GPsjksUZzpcGkNyjYtcI4xyDUo
# veO0hyTD4MmPfrVUj9z6BVWYbWg7mka97aSueik3rMvrg0XnRm7KMtXAhjBcTyzi
# YrLNueKNiOSWrAFKu75xqRdbZ2De+JKRHh09/SDPc31BmkZ1zcRfNN0Sidb9pSB9
# fvzZnkXftnIv231fgLrbqn427DZM9ituqBJR6L8FA6PRc6ZNN3SUHDSCD/AQ8rdH
# GO2n6Jl8P0zbr17C89XYcz1DTsEzOUyOArxCaC4Q6oRRRuLRvWoYWmEBc8pnol7X
# KHYC4jMYctenIPDC+hIK12NvDMk2ZItboKaDIV1fMHSRlJTYuVD5C4lh8zYGNRiE
# R9vcG9H9stQcxWv2XFJRXRLbJbqvUAV6bMURHXLvjflSxIUXk8A8FdsaN8cIFRg/
# eKtFtvUeh17aj54WcmnGrnu3tz5q4i6tAgMBAAGjggHdMIIB2TASBgkrBgEEAYI3
# FQEEBQIDAQABMCMGCSsGAQQBgjcVAgQWBBQqp1L+ZMSavoKRPEY1Kc8Q/y8E7jAd
# BgNVHQ4EFgQUn6cVXQBeYl2D9OXSZacbUzUZ6XIwXAYDVR0gBFUwUzBRBgwrBgEE
# AYI3TIN9AQEwQTA/BggrBgEFBQcCARYzaHR0cDovL3d3dy5taWNyb3NvZnQuY29t
# L3BraW9wcy9Eb2NzL1JlcG9zaXRvcnkuaHRtMBMGA1UdJQQMMAoGCCsGAQUFBwMI
# MBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMAsGA1UdDwQEAwIBhjAPBgNVHRMB
# Af8EBTADAQH/MB8GA1UdIwQYMBaAFNX2VsuP6KJcYmjRPZSQW9fOmhjEMFYGA1Ud
# HwRPME0wS6BJoEeGRWh0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3By
# b2R1Y3RzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNybDBaBggrBgEFBQcBAQRO
# MEwwSgYIKwYBBQUHMAKGPmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2Vy
# dHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMuY3J0MA0GCSqGSIb3DQEBCwUAA4IC
# AQCdVX38Kq3hLB9nATEkW+Geckv8qW/qXBS2Pk5HZHixBpOXPTEztTnXwnE2P9pk
# bHzQdTltuw8x5MKP+2zRoZQYIu7pZmc6U03dmLq2HnjYNi6cqYJWAAOwBb6J6Gng
# ugnue99qb74py27YP0h1AdkY3m2CDPVtI1TkeFN1JFe53Z/zjj3G82jfZfakVqr3
# lbYoVSfQJL1AoL8ZthISEV09J+BAljis9/kpicO8F7BUhUKz/AyeixmJ5/ALaoHC
# gRlCGVJ1ijbCHcNhcy4sa3tuPywJeBTpkbKpW99Jo3QMvOyRgNI95ko+ZjtPu4b6
# MhrZlvSP9pEB9s7GdP32THJvEKt1MMU0sHrYUP4KWN1APMdUbZ1jdEgssU5HLcEU
# BHG/ZPkkvnNtyo4JvbMBV0lUZNlz138eW0QBjloZkWsNn6Qo3GcZKCS6OEuabvsh
# VGtqRRFHqfG3rsjoiV5PndLQTHa1V1QJsWkBRH58oWFsc/4Ku+xBZj1p/cvBQUl+
# fpO+y/g75LcVv7TOPqUxUYS8vwLBgqJ7Fx0ViY1w/ue10CgaiQuPNtq6TPmb/wrp
# NPgkNWcr4A245oyZ1uEi6vAnQj0llOZ0dFtq0Z4+7X6gMTN9vMvpe784cETRkPHI
# qzqKOghif9lwY1NNje6CbaUFEMFxBmoQtB1VM1izoXBm8qGCAsswggI0AgEBMIH4
# oYHQpIHNMIHKMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
# A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUw
# IwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMSYwJAYDVQQLEx1U
# aGFsZXMgVFNTIEVTTjoxMkJDLUUzQUUtNzRFQjElMCMGA1UEAxMcTWljcm9zb2Z0
# IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUAG3F2jO4LEMVLwgKG
# XdYMN4FBgOCggYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAN
# BgkqhkiG9w0BAQUFAAIFAOXKJX8wIhgPMjAyMjAzMDMwMTE4NTVaGA8yMDIyMDMw
# NDAxMTg1NVowdDA6BgorBgEEAYRZCgQBMSwwKjAKAgUA5colfwIBADAHAgEAAgIK
# FjAHAgEAAgIRtTAKAgUA5ct2/wIBADA2BgorBgEEAYRZCgQCMSgwJjAMBgorBgEE
# AYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqGSIb3DQEBBQUAA4GB
# ALYBbjcbLE8sToUCNAWc4o33VZ0T44yfHgVPRNKyjfRfwLdgkaEP8XTKBRcGbJEZ
# ftjavGd4AIsbbnvrTWukXB2ER6+Bp6vM14hf5i9MMtG0wxhJIdf+l5FpckzMKere
# 5WoDlrA5GThHYYBaVv8qceoYxssd3ZggV9ObUt5JID7JMYIEDTCCBAkCAQEwgZMw
# fDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMd
# TWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAGhAYVVmblUXYoAAQAA
# AaEwDQYJYIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRAB
# BDAvBgkqhkiG9w0BCQQxIgQgr++jg8GnDlYIDG3CsL4rjHVMnBeUbHV+RqTq/1gg
# yM4wgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCDrCFTxOoGCaCCCjoRyBe1J
# SQrMJeCCTyErziiJ347QhDCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBD
# QSAyMDEwAhMzAAABoQGFVZm5VF2KAAEAAAGhMCIEIIboPLT3UDhKZd/4BwaXs2Fm
# OceS4/IqHYkerZNN+17xMA0GCSqGSIb3DQEBCwUABIICAMIl9wzVvVUenTOz1a4p
# Gp7BJR6Mnszzcp3lV606O0l7QZ8k/Bem5jSyXFduYVY11AY9WQLvgl5uf307pWri
# gPbSY0YSL9AwSVo/EVERlemng2hTB3V4CLisVT1wlBzGWBhu281t24QndoFokoLJ
# pAbnRQxpQuSi6HqNvxHodUHImkyEQqt0SYP0EMeTCiFnFRsaFZum0uLynO0PIkgr
# eeEE4LVTBIOwQGwycJIpKjSuAOR1eeve8+d3nXT4k/YGs6sx5dEZ93roreRkz71Z
# nLgr9TlnowSfevMUD/f1mZwCay/Fru81jvzlUBPQREfqQzKBlXQd/v0IsbTHMFIV
# iu47pkdT64o2lBPsTOuHozei27ibCa0Vp670JgHq+h0uGaVW9ppCX/nA+TiL922v
# YTTgshApV+9S1hqvEwzrsJIDiczh9bb+nrb4fXdZGR5ngyNXQWav7p84PIutaGUO
# aQbThPRKwZSjtqeE1eCR5lKsCOq4zBrW4WKKkdSfo/I8aGpTaypUfosciURANu13
# 64jjmKW42lor8tnItJvc8LF2vTj4Yd1uWD1YteIKrfpMRm3sDI66S/4diXD2MjvX
# qekbjKw/UYh/N3rfkWn58i0PJzBX5Rd9BPmG/KdTcsCxZAg0M6jhUu58plZKEJug
# 610T089PX4zkGYTHdxtlC0zs
# SIG # End signature block
