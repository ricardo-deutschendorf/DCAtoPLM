function Write-Section {

  param(
    [Parameter(Mandatory = $true)]
    [string]$Title,
    [switch]$NoLeadingBlank
  )

  if (-not $NoLeadingBlank) {
    Write-AnimatedLine ""
  }
  Write-AnimatedLine ("+" + ("-" * 68) + "+") -Color Gray
  Write-AnimatedLine ("| {0,-66} |" -f $Title) -Color White
  Write-AnimatedLine ("+" + ("-" * 68) + "+") -Color Gray
}

function Write-AnimatedLine {

  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$Message,
    [System.ConsoleColor]$Color = [System.ConsoleColor]::Gray,
    [ValidateRange(0, 2000)]
    [int]$DelayMilliseconds = $OutputDelayMilliseconds
  )

  Write-Host $Message -ForegroundColor $Color

  if ($DelayMilliseconds -gt 0) {
    Start-Sleep -Milliseconds $DelayMilliseconds
  }
}

function Write-SearchResultLine {

  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$Message,
    [System.ConsoleColor]$Color = [System.ConsoleColor]::Gray
  )

  Write-AnimatedLine `
    -Message $Message `
    -Color $Color `
    -DelayMilliseconds $script:SearchResultDelayMilliseconds
}

function Write-Success {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Message
  )

  Write-AnimatedLine "  $Message" -Color Green
}

function Write-Failure {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Message
  )

  Write-AnimatedLine "  Algo deu errado: $Message" -Color Red
}

function Write-Warn {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Message
  )

  Write-AnimatedLine "  Atencao: $Message" -Color Yellow
}

function Write-Info {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Message
  )

  Write-AnimatedLine "  $Message" -Color Gray
}
