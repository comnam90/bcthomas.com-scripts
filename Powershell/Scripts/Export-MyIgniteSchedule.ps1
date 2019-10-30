<#
    .Notes
    All based off the work done by @d_bargna here https://github.com/spallison/myignite2outlook/blob/master/I2outlook.ps1
    #>
[CmdletBinding(DefaultParameterSetName = 'ICS')]
param(
    [string]$uri = "https://api-myignite.techcommunity.microsoft.com/api/schedule/sessions",
    #-Put your auth token here - between the single quotes, do not share your token with anyone, do not distribute it :-)
    [parameter(Mandatory)]
    [string]$xjwt,

    [parameter()]
    [ValidatePattern("^\w{3,4}\d{2,4}$")]
    [string[]]$SessionCode,

    [ValidateSet('Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday')]
    [string[]]$Day = @('Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'),

    [parameter(ParameterSetName = 'ICS')]
    [ValidateScript(
        {
            if (Test-Path $_) {
                $True
            } else {
                Throw "$_ is not a valid path"
            }
        }
    )]
    [string]$OutputFolder = (Get-Location).Path
)

#---------Functions
# JWT from #https://gallery.technet.microsoft.com/JWT-Token-Decode-637cf001
function Convert-FromBase64StringWithNoPadding([string]$data) {
    $data = $data.Replace('-', '+').Replace('_', '/')
    switch ($data.Length % 4) {
        0 { break }
        2 { $data += '==' }
        3 { $data += '=' }
        default { throw New-Object ArgumentException('data') }
    }
    return [System.Convert]::FromBase64String($data)
}

function Convert-FromEncodedJWT([string]$rawToken) {
    $parts = $rawToken.Split('.');
    $headers = [System.Text.Encoding]::UTF8.GetString((Convert-FromBase64StringWithNoPadding $parts[0]))
    $claims = [System.Text.Encoding]::UTF8.GetString((Convert-FromBase64StringWithNoPadding $parts[1]))
    $signature = (Convert-FromBase64StringWithNoPadding $parts[2])

    $customObject = [PSCustomObject]@{
        headers   = ($headers | ConvertFrom-Json)
        claims    = ($claims | ConvertFrom-Json)
        signature = $signature
    }

    Write-Verbose -Message ("JWT`r`n.headers: {0}`r`n.claims: {1}`r`n.signature: {2}`r`n" -f $headers, $claims, [System.BitConverter]::ToString($signature))
    return $customObject
}

function Get-JwtTokenData {
    [CmdletBinding()]  
    Param
    (
        # Param1 help description
        [Parameter(Mandatory = $true)]
        [string] $Token,
        [switch] $Recurse
    )
    
    if ($Recurse) {
        $decoded = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Token))
        Write-Host("Token") -ForegroundColor Green
        Write-Host($decoded)
        $DecodedJwt = Convert-FromEncodedJWT -rawToken $decoded
    } else {
        $DecodedJwt = Convert-FromEncodedJWT -rawToken $Token
    }
    #Write-Host("Token Values") -ForegroundColor Green
    Write-Verbose ($DecodedJwt | Select-Object headers, claims | ConvertTo-Json)
    return $DecodedJwt
}
#----- end JWT from #https://gallery.technet.microsoft.com/JWT-Token-Decode-637cf001

function New-IcsEvent {
    [OutputType([System.IO.FileInfo[]])]
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param
    (
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [datetime[]]
        $StartDate,

        [Parameter()]
        [string]
        $Path = (Get-Location).Path,

        [Parameter()]
        [string]
        $fileName,

        [Parameter(Mandatory)]
        [string]
        $Subject,

        [Parameter()]
        [string]
        $Location,

        [Parameter()]
        [timespan]
        $Duration = '01:00:00',

        [Parameter()]
        [string]
        $EventDescription,

        [Parameter()]
        [switch]
        $PassThru,

        [ValidateSet('Free', 'Busy')]
        [string]
        $ShowAs = 'Busy',

        [ValidateSet('Private', 'Public', 'Confidential')]
        [string]
        $Visibility = 'Public',

        [string[]]
        $Category
    )

    begin {
        # Custom date formats that we want to use
        $icsDateFormat = "yyyyMMddTHHmmssZ"
    }

    process {
        # Checkout RFC 5545 for more options
        foreach ($Date in $StartDate) {
            if (!$fileName) {
                $fileName = Join-Path -Path $Path -ChildPath "$($Date.ToString($icsDateFormat)).ics"
            } else {
                $fileName = Join-Path -Path $Path -ChildPath "$($fileName).ics"
            }
            $event = @"
BEGIN:VCALENDAR
VERSION:2.0
METHOD:PUBLISH
PRODID:-//JHP//We love PowerShell!//EN
BEGIN:VEVENT
UID: $([guid]::NewGuid())
CREATED: $((Get-Date).ToUniversalTime().ToString($icsDateFormat))
DTSTAMP: $((Get-Date).ToUniversalTime().ToString($icsDateFormat))
LAST-MODIFIED: $((Get-Date).ToUniversalTime().ToString($icsDateFormat))
CLASS:$Visibility
CATEGORIES:$($Category -join ',')
SEQUENCE:0
DTSTART:$($Date.ToUniversalTime().ToString($icsDateFormat))
DTEND:$($Date.ToUniversalTime().Add($Duration).ToString($icsDateFormat))
DESCRIPTION: $EventDescription
SUMMARY: $Subject
LOCATION: $Location
TRANSP:$(if($ShowAs -eq 'Free') {'TRANSPARENT'})
END:VEVENT
END:VCALENDAR
"@
            if ($PSCmdlet.ShouldProcess($fileName, 'Write ICS file')) {
                Write-Verbose "Writing ICS to $FileName"
                $event | Out-File -FilePath $fileName -Encoding utf8 -Force
                if ($PassThru) { Get-Item -Path $fileName }
            }
        }
    }
}


#-END Functions

## Lets Go!
#first we check the security token
$token = $null
$token = Get-JwtTokenData $xjwt

if ($token.claims.scopes -match "myignite") {
    Write-Verbose "Bingo! your token looks good...lets grab the data"
    #now we grab the json data :-)
    #set TLS to v 1.2 otherwise connection will be closed!
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add('x-jwt', $xjwt)
    try {
        $jsondata = Invoke-RestMethod -Uri $uri -Headers $headers -UseBasicParsing -erroraction Stop
    } catch {
        Write-Error "I cannot get the JSON data from the api server."
        Write-Error "$($error[0])"
        break
    }
    #got some data? make sure its not empty
    if ($null -ne $jsondata) {
        foreach ($item in $jsondata) {
            if ($null -ne $item.startDateTime) {
                if ($null -eq $SessionCode -or $item.sessionCode -iin $SessionCode) {
                    if (([datetime]$item.startDateTime).ToUniversalTime().addhours(-5).DayOfWeek.ToString() -iin $Day) {
                        if ($PSCmdlet.ParameterSetName -ieq "ICS") {
                            [DateTime]$StartTime = $item.startDateTime
                            [DateTime]$EndTime = $item.endDateTime
                            $FileName = "$($StartTime.ToUniversalTime().DayOfWeek) - $($item.sessionCode) - $($item.title.Replace('/','').Replace('\','').Replace(':','-'))"
                            $Duration = New-TimeSpan -end $EndTime -Start $StartTime
                            $DurationString = "{0}:{1}:{2}" -f $Duration.Hours, $Duration.Minutes, $Duration.Seconds
                            $EventDescription = $item.description
                            $EventDescription += "\n\n\nSession Link: https://myignite.techcommunity.microsoft.com/sessions/$($item.sessionId)"
                            $potition = 0
                            $EventDescription += "\n\nSpeaker Links:"
                            $item.speakerIds.Foreach{
                                $SpeakerName = $item.speakerNames[$potition]
                                $EventDescription += "\n - $($SpeakerName): https://myignite.techcommunity.microsoft.com/speaker/$($psitem)"
                                $potition++
                            }

                            New-IcsEvent -StartDate $StartTime `
                                -fileName $FileName `
                                -Subject "$($item.sessionCode) - $($item.title)"`
                                -Location $item.location `
                                -Duration $DurationString `
                                -EventDescription $EventDescription `
                                -ShowAs Busy `
                                -Visibility Public `
                                -Path $OutputFolder
                        }
                    }
                }
            } else {
                Write-Warning "$("$($item.sessionCode) - $($item.title)") doesn't have a start time"
            }
        }
    } else {
        Write-Error "No JSON data, sorry!!"
    }
} else {
    Write-Error "looks like the auth token is broken/invalid...sorry. have you removed all the junk from the start end?"
}
