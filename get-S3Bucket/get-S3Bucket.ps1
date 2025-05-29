# This script is a PowerShell cmdlet for interacting with an S3 bucket.
# It allows listing the keys in the bucket or downloading the contents to a local directory.

[CmdletBinding()]
param (
    # Mandatory parameter specifying the S3 bucket URL
    [Parameter(mandatory = $true)]
    [string]
    $S3Bucket,

    # Optional parameter specifying the base directory for downloads (default: d:\<bucket_name>)
    [Parameter()]
    [string]
    $OutputFolder = "d:\$S3Bucket",

    # Optional switch to list keys in the S3 bucket instead of downloading
    [Parameter()]
    [switch]
    $listkeys
)

try {
    # Fetch the XML response from the S3 bucket
    $xmlObject = [xml](Invoke-WebRequest -uri $S3Bucket -ErrorAction Stop)

    # If the listkeys switch is provided, output the keys in the S3 bucket
    if ($listkeys) {
        Write-Output "Listing all content keys in the S3 Bucket"
        $xmlObject.ListBucketResult.Contents.key
    } else {
        # Iterate through each key in the bucket
        foreach ($key in $xmlobject.ListBucketResult.Contents.key) {
            try {
                # Construct the full URL for the key
                $url = $S3Bucket + $key

                # Split the key into parts using '/' as the delimiter
                $keyParts = $key -split '/'

                # Create the folder structure based on the key parts
                $folderPath = $OutputFolder
                for ($i = 0; $i -lt $keyParts.Length - 1; $i++) {
                    $part = $keyParts[$i]
                    $folderPath = Join-Path -Path $folderPath -ChildPath $part
                    if (!(Test-Path -Path $folderPath -PathType Container)) {
                        New-Item -Path $folderPath -ItemType Directory -ErrorAction Stop
                    }
                }

                # Extract the filename from the key parts
                $filename = $keyParts[$keyParts.Length - 1]
                Write-Host "Downloading $filename from $url"

                # Download the file to the constructed folder path
                Invoke-WebRequest -Uri $url -OutFile "$folderPath\$filename" -ErrorAction Stop
            } catch {
                Write-Error "Failed to process key: $key. Error: $_"
            }
        }
    }
} catch {
    Write-Error "Failed to fetch data from S3 bucket: $S3Bucket. Error: $_"
}