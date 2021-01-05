#   _   _                      _                _                                              __   
#  | \ | |                    | |              | |                                            /  |  
#  |  \| | _____      ________| |     ___   ___| | _____  ___ _ __ ___  ___ _ __    _ __  ___ `| |  
#  | . ` |/ _ \ \ /\ / /______| |    / _ \ / __| |/ / __|/ __| '__/ _ \/ _ \ '_ \  | '_ \/ __| | |  
#  | |\  |  __/\ V  V /       | |___| (_) | (__|   <\__ \ (__| | |  __/  __/ | | |_| |_) \__ \_| |_ 
#  \_| \_/\___| \_/\_/        \_____/\___/ \___|_|\_\___/\___|_|  \___|\___|_| |_(_) .__/|___/\___/ 
#                                                                                  | |              
#                                                                                  |_|              
#
#                                   Author: Roel van der Wegen             
#                                Initial development December 2020                   
#
<#
    Script Changelog
    1.0     [December 2020]    Roel van der Wegen      - Script developed
    1.1     [January 2020]     Roel van der Wegen      - Cleaned up image creation and added update check
    1.2     [January 2020]     Roel van der Wegen      - Further cleaned up image creation and clarified script comments
#>
<# 
    .SYNOPSIS
    Creates a new lockscreen wallpaper from 3 source files.

    .DESCRIPTION
    Creates a new lockscreen wallpaper from 3 source files. 
    Functionality includes an update check, path validation, overlaying an image, writing text on the wallpaper and CMTrace compatible logging.

    .CREDITS
    Credit to Dmitry Maystrenko (PM Kuban) and Lev Papayan (PM Russia) for the original lockscreen wallpaper concept.
#>

# Hide PowerShell Console
Add-Type -Name Window -Namespace Console -MemberDefinition '
[DllImport("Kernel32.dll")]
public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")]
public static extern bool ShowWindow(IntPtr hWnd, Int32 nCmdShow);
'
$consolePtr = [Console.Window]::GetConsoleWindow()
[Console.Window]::ShowWindow($consolePtr, 0) | Out-Null

# Load assembly
Add-Type -AssemblyName System.Drawing

# Variables
$Title = "New-Lockscreen"
$Generate = $false
$LogFile = "$env:temp\$Title.log"

# Define paths
$BlankSrcPath = "path-to\lockscreenbg-blank.bmp" # Your blank wallpaper
$OverlaySrcPath = "path-to\lockscreenbg-overlay.bmp" # Image that has to be overlayed on it. Note that this is coded with the assumption that the two images are the same size with the overlay being mostly transparent.
$MOTDSrcPath = "path-to\MOTD.txt" # MOTD message
$FinalDestPath = "path-to\lockscreenbg.bmp" # Final result file, point your GPO lockscreen setting to this location

# Start the image creation
Function Start-Script {
    Try {
        # Put paths in array
        $Paths = @(
            $BlankSrcPath,
            $OverlaySrcPath,
            $MOTDSrcPath
        )

        # Validate source paths
        foreach ($path in $paths) {
            if (!(Test-Path $path)) {
                Write-Log -Type "Error" -LogMsg "$Path was not found!" -Console -Logpath $LogFile
                throw "$path was not found!"
            }
        }

        # Check if source files exist that are newer than $FinalDestPath
        if (Test-Path $FinalDestPath) {
            foreach ($path in $paths) {
                if (Test-Path $path -NewerThan (Get-ChildItem $FinalDestPath).LastWriteTime) {
                    Write-Log -Type "Info" -LogMsg "$path date is newer than current lockscreen image." -Console -Logpath $LogFile
                    $Generate = $true
                }
                else {
                    Write-Log -Type "Info" -LogMsg "$path date is not newer than current lockscreen image." -Console -Logpath $LogFile
                }
            }
        }
        else {
            Write-Log -Type "Info" -LogMsg "Image does not yet exist, skipping update check." -Console -Logpath $LogFile 
            $Generate = $true
        }

        # Check if $Generate variable is $true
        if (!($Generate)) {
            Write-Log -Type "Info" -LogMsg "No new image generation needed. Stopping script." -Console -Logpath $LogFile
            exit
        }
        else {
            Write-Log -Type "Info" -LogMsg "Generating new image." -Console -Logpath $LogFile
        }

        # Get blank source image
        $BlankSrcImg = [System.Drawing.Image]::FromFile($BlankSrcPath)

        # Create a blank canvas from $BlankScrImg
        $CompImg = new-object System.Drawing.Bitmap([int]($BlankSrcImg.width)),([int]($BlankSrcImg.height))

        # Intialize Graphics
        $Image = [System.Drawing.Graphics]::FromImage($CompImg)
        $Image.SmoothingMode = "AntiAlias"

        # Sizing
        $Rectangle = New-Object Drawing.Rectangle 0, 0, $BlankSrcImg.Width, $BlankSrcImg.Height

        # Add blank source image
        $Image.DrawImage($BlankSrcImg, $Rectangle, 0, 0, $BlankSrcImg.Width, $BlankSrcImg.Height, ([Drawing.GraphicsUnit]::Pixel))

        # Add overlay image
        Add-Overlay -OverlaySrcPath $OverlaySrcPath -ErrorAction Continue

        # Add computername
        Add-Text -Text $env:COMPUTERNAME -TextSize "40" -FontType "Segoe UI" -Color "#ffffff" -HorAlign "Far" -VerAlign "Near" -ErrorAction Continue

        # Add MOTD
        $MOTDtext = Get-Content $MOTDSrcPath
        Add-Text -Text $MOTDtext -TextSize "60" -FontType "Segoe UI" -Color "#ffffff" -HorAlign "Center" -VerAlign "Far" -ErrorAction Continue

        # Save image
        $CompImg.Save($FinalDestPath)

        # Test if image was created/modified
        if ((Test-Path $FinalDestPath)) {
            if ((Get-ChildItem $FinalDestPath).lastwritetime -gt [datetime]::today) {
                Write-Log -Type "Info" -LogMsg "Image was succesfully created/modified" -Console -Logpath $LogFile
            }
            else {
                Write-Log -Type "Warning" -LogMsg "Image exists but was not modified at current script run" -Console -Logpath $LogFile
            }
        }
        else {
            Write-Log -Type "Error" -LogMsg "Image creation failed!" -Console -Logpath $LogFile
            throw "Image creation failed!"
        }
    }
    Catch {
        Write-Log -Type "Error" -LogMsg "Something went wrong!" -Console -Logpath $LogFile
        Write-Log -Type "Error" -LogMsg $_.Exception.GetType().FullName -Console -Logpath $LogFile
        Write-Log -Type "Error" -LogMsg $_.Exception.Message -Console -Logpath $LogFile 
    }
    Finally {
        if ($Generate) {
            # Clean up
            $BlankSrcImg.Dispose()
            $CompImg.Dispose()
            $Image.Dispose()
        }
    }
}

# Write text on canvas
Function Add-Text {
    [CmdletBinding()]
    param (
        [Parameter()][String] $Text=" ", # Defaults to a space to prevent errors
        [Parameter()][String] $FontType="Segoe UI", # Defaults to Segoe UI
        [Parameter()][String] $Color="#ffffff", # Defaults to white
        [Parameter()][string] $TextSize="60",
        [Parameter(Mandatory=$true)][ValidateSet("Near", "Center", "Far")][String] $HorAlign,
        [Parameter(Mandatory=$true)][ValidateSet("Near", "Center", "Far")][String] $VerAlign
    )

    # Rectangle, needed for position
    $rect = [System.Drawing.RectangleF]::FromLTRB(0, 0, $BlankSrcImg.Width, $BlankSrcImg.Height)

    # Style text
    $Brush = New-Object Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml($Color))

    # Define font
    $Font = new-object System.Drawing.Font($FontType, $TextSize)

    # Set location
    $format = [System.Drawing.StringFormat]::GenericDefault
    $format.Alignment = [System.Drawing.StringAlignment]::$HorAlign
    $format.LineAlignment = [System.Drawing.StringAlignment]::$VerAlign

    # Draw text
    $Image.DrawString($Text, $Font, $Brush, $Rect, $format)
}

# Overlay $OverLayScrPath on canvas
Function Add-Overlay {
    [CmdletBinding()]
    param (
        [Parameter()][String] $OverlaySrcPath
    )
    # Get overlay source image
    $OverlaySrcImg = [System.Drawing.Image]::FromFile($OverlaySrcPath)

    # Draw overlay image onto blank canvas
    $Image.DrawImage($OverlaySrcImg, $Rectangle, 0, 0, $BlankSrcImg.Width, $BlankSrcImg.Height, ([Drawing.GraphicsUnit]::Pixel))

    # Clean up
    $OverlaySrcImg.Dispose()
}

# Log function
Function Write-Log{
    [CmdletBinding()]
    param(
        # Message to be logged
        [Parameter(Mandatory=$True)]
        [String]$LogMsg,

        # Path to the log file, defaults to false so if no input is given there will not be an entry in the logfile
        [Parameter(Mandatory=$false)]
        [String]$Logpath=$false,

        # Used to print log entries to a GUI console
        [parameter(Mandatory=$false)]
        [Switch]$GUI=$false,

        # Used to print log entries to the Powershell console
        [parameter(Mandatory=$false)]
        [Switch]$Console=$false,

        # Used to determine the log entry type
        [Parameter(Mandatory=$true)]
        [ValidateSet("Info", "Warning", "Error")]
        [String]$Type="Info"
    )

    # Determine the log entry type
    switch ($Type) {
        "Info" { [int]$Type = 1 }
        "Warning" { [int]$Type = 2 }
        "Error" { [int]$Type = 3 }
    }

    # Date
    $LogDate = Get-Date -Format "d-M-yyyy"

    # Time
    $LogTime = Get-Date -Format "HH:mm:ss"

    # Retrieve the calling function name
    $GetFunctionName = [string]$(Get-PSCallStack)[1].FunctionName

    # Used to print a log entry to a GUI console
    if ($GUI -eq $true) {
        switch ($Type) {
            "1" { $GUIconsole.SelectionColor = 'black'; $GUIconsole.AppendText($LogMsg + "`r`n") }
            "2" { $GUIconsole.SelectionColor = 'orange'; $GUIconsole.AppendText($LogMsg + "`r`n") }
            "3" { $GUIconsole.SelectionColor = 'red'; $GUIconsole.AppendText($LogMsg + "`r`n") }
        }
    }

    # Used to print a log entry to the Powershell console
    if ($Console -eq $true) {
        switch ($Type) {
            "1" { Write-Host $LogMsg }
            "2" { Write-Host $LogMsg }
            "3" { Write-Host $LogMsg }
        }
    }

    # Used to print a log entry to a logfile
    if ($LogPath) {
        # Create a CMTrace compatible log entry
        $Content = "<![LOG[$LogMsg]LOG]!>" +`
            "<time=`"$(Get-Date -Format "HH:mm:ss.ffffff")`" " +`
            "date=`"$(Get-Date -Format "M-d-yyyy")`" " +`
            "component=`"$GetFunctionName`" " +`
            "context=`"$([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)`" " +`
            "type=`"$Type`" " +`
            "thread=`"$([Threading.Thread]::CurrentThread.ManagedThreadId)`" " +`
            "file=`"C:\stuff.ps1`">"

        # Add log entry to log file
        Out-File -InputObject $Content -Append -NoClobber -Encoding Default -FilePath $Logpath -WhatIf:$False
    }

    # Example formatting if you need a full log entry in the GUIConsole
    # ($LogDate + " " + $LogTime + " | Function: " + $GetFunctionName + " | Message: " + $LogMsg + "`r`n")
    # Example formatting if you need a full log entry in the Powershell Console
    # ($LogDate + " " + $LogTime + " | Function: " + $GetFunctionName + " | Message: " + $LogMsg)
} # End of logging function

Start-Script
