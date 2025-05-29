<#
.SYNOPSIS
    Determines if a website is hosted in an open S3 bucket.

.DESCRIPTION
    This script sends an HTTP request to a given website and inspects the response headers
    to check if the website is hosted in an Amazon S3 bucket. It also checks for public access
    by attempting to list the bucket contents.

.PARAMETER Website
    The URL of the website to check.

.EXAMPLE
    .\get-IsS3Hosted.ps1 -Website "http://example.com"
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$Website
)

function Test-S3Hosting {
    param (
        [string]$Url
    )

    try {
        # Send a HEAD request to the website
        $response = Invoke-WebRequest -Uri $Url -Method Head -ErrorAction Stop

        # Check for S3-specific headers
        if ($response.Headers["x-amz-id-2"] -or $response.Headers["x-amz-request-id"]) {
            Write-Host "The website appears to be hosted in an Amazon S3 bucket."

            # Attempt to list the bucket contents
            $bucketResponse = Invoke-WebRequest -Uri $Url -Method Get -ErrorAction SilentlyContinue
            if ($bucketResponse.StatusCode -eq 200 -and $bucketResponse.Content -match "<ListBucketResult") {
                Write-Host "The S3 bucket is publicly accessible."
            } else {
                Write-Host "The S3 bucket is not publicly accessible."
            }
        } else {
            Write-Host "The website does not appear to be hosted in an Amazon S3 bucket."
        }
    } catch {
        Write-Host "An error occurred: $($_.Exception.Message)"
    }
}

function Get-S3BucketUrl {
    param (
        [string]$Url
    )

    try {
        # Send a HEAD request to the website
        $response = Invoke-WebRequest -Uri $Url -Method Head -ErrorAction Stop

        # Check for S3-specific headers
        if ($response.Headers["x-amz-id-2"] -or $response.Headers["x-amz-request-id"]) {
            Write-Host "The website appears to be hosted in an Amazon S3 bucket."

            # Extract the bucket URL from the response headers if available
            if ($response.Headers["x-amz-bucket-region"]) {
                $region = $response.Headers["x-amz-bucket-region"]
                $bucketUrl = "https://$Url.s3.$region.amazonaws.com"
                Write-Host "The S3 bucket URL is: $bucketUrl"
            } else {
                Write-Host "Could not determine the S3 bucket URL from the headers."
            }
        } else {
            Write-Host "The website does not appear to be hosted in an Amazon S3 bucket."
        }
    } catch {
        Write-Host "An error occurred: $($_.Exception.Message)"
    }
}

# Run the function
Test-S3Hosting -Url $Website

# Run the function to determine the S3 bucket URL
Get-S3BucketUrl -Url $Website