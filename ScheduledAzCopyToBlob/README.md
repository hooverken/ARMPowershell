# Automated file copies to Azure blob storage based on last-modified timestamp

This PowerShell script moves files from a local path to an Azure blob container based on the date they were last modified.  

It is intended to be run as a scheduled task on a system which has access to the directory containing the source files.

Authentication uses an EntraID (Azure AD) Service Principal.

## Prerequisites

Before starting, make sure you have the following:

- Download the **[AzCopy](https://learn.microsoft.com/azure/storage/common/storage-use-azcopy-v10)** tool
- Identify the user account that will "own" the scheduled task on the machine that will run the job.  This can be a local or domain account.

## Setting Up

### Azure Setup:
* Create a [service principal that uses a self-signed certificate for authentication](https://learn.microsoft.com/en-us/entra/identity-platform/howto-authenticate-service-principal-powershell#create-service-principal-with-self-signed-certificate).  Make sure it has a meaningful name.  A self-signed certificate will be created as part of this process and stored on the local machine.
* Identify the storage account and blob container that will be the destination for the files that are moved.  Grant the service principal the `Storage Blob Data Contributor` IAM role on the **container** and the `Reader` role on the **storage account**. *(Read access to the storage account is necessary for the SP to "see" the storage account and the container)*
* Export the self-signed certificate created for the SP into a .PFX file with a robust password.

### On the machine that will run the scheduled task:
* Use [this process from the Powershell Cookbook](https://powershellcookbook.com/recipe/PukO/securely-store-credentials-on-disk) to create a XML file which has the **application ID of the service principal you created** as the username and the **encrypted password for the .PFX file** that you created above as the password.

> The AzCopy.exe utility must be in the same directory as the script.

#### TEST by executing the script interactively

* Make sure you're logged in as the user that will "own" the scheduled task.  This user must also have created the XML file with the credentials in it.
* Gather the necessary files together into a directory:
    * The `ScheduledFileMoveToAzure.ps1` file
    * The `AzCopy.exe` executable (or confirm that it's executable via the path)
    * The `PFX`` file with the SP's certificate and private key in it
    * The `XML`` file with the application ID of the SP and the password for the PFX file.
* Create a subdirectory named `AzCopyLogs`.  This is where the logs from the runs will be stored:
    * *Tip:  Set this directory to have NTFS compression enabled since the (text) log files are chatty.  Also consider pruning the directory periodically to keep it from growing too large and causing problems.*
* Run the script by providing the parameters via the command line.
    * *Tip:  Use a text editor like Notepad to assemble the parameters and then paste them into the Powershell window.*

Example command line:

`ScheduledFileMoveToAzure.ps1 -servicePrincipalCertFilePath .\SPCertificate.pfx -servicePrincipalCredsFile .\ServicePrincipalCreds.xml -tenantId <your tenant ID> -storageAccountName mystorageaccount -containerName targetcontainer -MaxAgeDays 90 -sourcePath <full path to source directory>`

**Do not move on to creating the scheduled task until this test runs successfully.**

### Create the scheduled task

1. Log into the machine that will run the scheduled task as the user that will "own" the task in the Scheduler.
2. Open the task scheduler, right-click on "Task Scheduler Library" and select "Create Basic Task..."
3. On the first screen, give the task a descriptive name like "Nightly File archive to Azure"
4. On the `Trigger` Screen, select the interval you want for the move to occur, such as `Daily`, and configure the interval as needed.
5. On the `Action` screen, choose `Start a Program` and enter the following:
    * For "Program/Script", browse to and select the script
    * For "Add Arguments(Optional)" add the parameters the script needs (see below)
    * For "Start In (optional)" paste in the full path to the directory where the script, .pfx file and the .xml file are located.
6. Hit "Finish" when everything looks correct.

You can test the script by simply running the scheduled task.

## Testing and Debugging

To test the script, simply run the scheduled task.  The script does a bit of setup and then invokes AzCopy to do the file moves.

AzCopy will create a log every time it runs in a subdirectory called `AzCopyLogs` so check there to verify which files were copied during a particular run.

 > Note about the encrypted credentials file:  The XML file that is created can only be decrypted by the **same user** that created it **on the same machine** that it was created on so it is not portable from machine to machine - you will need to repeat the process to move this to a new machine even if the username/password are the same.

## License

THIS IS DEMO/EXAMPLE CODE ONLY AND NOT FOR PRODUCTION USE. 

Licensed under the [MIT License](LICENSE).
