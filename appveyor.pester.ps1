# This script will invoke pester tests
# It should invoke on PowerShell v2 and later
# We serialize XML results and pull them in appveyor.yml

#If Finalize is specified, we collect XML output, upload tests, and indicate build errors
param(
    [switch]$Finalize,
    [switch]$Success
)


#Initialize some variables, move to the project root
    $PSVersion = $PSVersionTable.PSVersion.Major
    $TestFile = "TestResultsPS$PSVersion.xml"
    $ProjectRoot = $ENV:APPVEYOR_BUILD_FOLDER
    Set-Location $ProjectRoot
   

#Run a test with the current version of PowerShell
    if(-not $Finalize)
    {
        "`n`tSTATUS: Testing with PowerShell $PSVersion`n"
    
        Import-Module Pester

        Invoke-Pester -Path "$ProjectRoot" -OutputFormat NUnitXML -OutputFile "$ProjectRoot\$TestFile" -PassThru |
            Export-Clixml -Path "$ProjectRoot\PesterResults$PSVersion.xml"
    }

#If finalize is specified, check for failures and 
    else
    {
        #Show status...
            $AllFiles = Get-ChildItem -Path $ProjectRoot\*Results*.xml | Select -ExpandProperty FullName
            "`n`tSTATUS: Finalizing results`n"
            "COLLATING FILES:`n$($AllFiles | Out-String)"
 
        #Upload results for test page
            Get-ChildItem -Path "$ProjectRoot\TestResultsPS*.xml" | Foreach-Object {
            
                [xml]$content = Get-Content $_.FullName
                $content.'test-results'.'test-suite'.type = "Powershell"
                $content.Save($_.FullName)
        
                $Address = "https://ci.appveyor.com/api/testresults/nunit/$($env:APPVEYOR_JOB_ID)"
                $Source = $_.FullName

                "UPLOADING FILES: $Address $Source"

                (New-Object 'System.Net.WebClient').UploadFile( $Address, $Source )
            }

        #What failed?
            $Results = @( Get-ChildItem -Path "$ProjectRoot\PesterResults*.xml" | Import-Clixml )
            
            $FailedCount = $Results |
                Select -ExpandProperty FailedCount |
                Measure-Object -Sum |
                Select -ExpandProperty Sum
    
            if ($FailedCount -gt 0) {

                $FailedItems = $Results |
                    Select -ExpandProperty TestResult |
                    Where {$_.Passed -notlike $True}

                "FAILED TESTS SUMMARY:`n"
                $FailedItems | ForEach-Object {
                    $Test = $_
                    [pscustomobject]@{
                        Describe = $Test.Describe
                        Context = $Test.Context
                        Name = "It $($Test.Name)"
                        Result = $Test.Result
                    }
                } |
                    Sort Describe, Context, Name, Result |
                    Format-List

                throw "$FailedCount tests failed."
            }
    }

if ($success) {
    $Module = 'XKCD'
      $Publish = $true
      $Version = $Env:APPVEYOR_BUILD_VERSION

      $ModuleData = (Get-Module $Module)

      If ($Version -and $Version -ne '0.0.1') {
          Try {
              Update-ModuleManifest -Path ($ModuleData.Path) -ModuleVersion $Version
              Write-Verbose "Module manifest updated with -ModuleVersion $Version"

              If ($Publish) {   
                  Try {
                      Publish-Module -Name $Module -NuGetApiKey $Env:PSGalleryKey 
                      Write-Verbose "Published $Module to PSGallery"
                  } Catch { 
                      Write-Error "Could not publish to PSGallery." -Category ConnectionError
                  }
              }

          } Catch { 
              Write-Error "Could not update module manifest." -Category ConnectionError
          }

      }Else{
          Write-Error "No version specified." -Category InvalidArgument
      }
}
