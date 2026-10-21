param(
    [Parameter(Mandatory = $true, ValueFromRemainingArguments = $true)]
    [string[]]$ComputerName
)

foreach ($name in $ComputerName) {

    try {
        $reply = Test-Connection -ComputerName $name -Count 1 -ErrorAction Stop

        # Grab the first reply object
        $first = $reply | Select-Object -First 1

        # Try IPv4Address first (newer PS), then Address (classic Win32_PingStatus)
        $ip = $first.IPv4Address
        if (-not $ip) { $ip = $first.Address }

        # If it's a System.Net.IPAddress, convert to string
        if ($ip -is [System.Net.IPAddress]) {
            $ip = $ip.IPAddressToString
        }

        if ([string]::IsNullOrWhiteSpace($ip)) {
            Write-Host "$name : UP (IP unknown)" -ForegroundColor Yellow
        } else {
            Write-Host "$name : UP ($ip)" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "$name : DOWN (no response)" -ForegroundColor Red
    }
}
