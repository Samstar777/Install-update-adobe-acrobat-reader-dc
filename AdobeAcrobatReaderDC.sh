#!/bin/bash


SCRIPT=$( basename "${0}" )


##setParams
properName="Adobe Acrobat DC"                 ## Edit this to change the name that appears log output
installerString="AcroRdrDC"                   ## Name (or part of) of pkg filename
appPath="/Applications/Adobe Acrobat Reader DC.app"       ## Install location
installType="PKG"                     ## Just for reference
fileType="dmg"                            
URL=$( curl --silent --fail -H "Sec-Fetch-Site: same-origin" -H "Accept-Encoding: gzip, deflate, br" -H "Accept-Language: en-US;q=0.9,en;q=0.8" -H "DNT: 1" -H "Sec-Fetch-Mode: cors" -H "X-Requested-With: XMLHttpRequest" -H "Referer: https://get.adobe.com/reader/enterprise/" -H "Accept: */*" "https://get.adobe.com/reader/webservices/json/standalone/?platform_type=Macintosh&platform_dist=OSX&platform_arch=x86-32&language=English&eventname=readerotherversions" | grep -Eo '"download_url":.*?[^\\]",' | head -n 1 | cut -d \" -f 4 )
evalFunc=$( curl --silent --fail -H "Sec-Fetch-Site: same-origin" -H "Accept-Encoding: gzip, deflate, br" -H "Accept-Language: en-US;q=0.9,en;q=0.8" -H "DNT: 1" -H "Sec-Fetch-Mode: cors" -H "X-Requested-With: XMLHttpRequest" -H "Referer: https://get.adobe.com/reader/enterprise/" -H "Accept: */*" "https://get.adobe.com/reader/webservices/json/standalone/?platform_type=Macintosh&platform_dist=OSX&platform_arch=x86-32&language=Dutchh&eventname=readerotherversions" | grep -Eo '"Version":.*?[^\\]",' | head -n 1 | cut -d \" -f 4 )
curlFlag="-L"
CFVers="CFBundleVersion"


## Start Functions

function ScriptLogging () {
    echo "[$SCRIPT] [$(date +"%Y-%m-%d %T")] " "$1" 
}


function getCurrVers () {

## Description: This function is called to get current version and download URL

echo "[Stage ${StepNum}]: Determining current version of ${properName}..."

currVers="${evalFunc}"

if [[ ! -z "${currVers}" ]]; then
    echo "DEBUG: current version of ${properName} found was: $currVers"

    ## If we pulled back a current version, get the download location
    download_url="${URL}"

    ## Check the URL to make sure its valid
    curl -sfI "$download_url" 2>&1 > /dev/null
    last_exit=$?

    if [[ "$last_exit" == "0" ]]; then
            ## Get Installed version
            getinstVersion
    else
        echo "There was a problem getting the download information."
        dlError
    fi
else
    ## Else on error, run the getVersErr function
    getVersErr
fi
}


function getinstVersion () {

## Description: This function is called to get the installed application/plug-in version on disk.

let StepNum=$StepNum+1
echo "[Stage ${StepNum}]: Determining installed version of ${properName}..."

if [[ -e "${appPath}" ]]; then
    instVers=$( defaults read "${appPath}/Contents/Info.plist" ${CFVers} 2>/dev/null)

    if [[ ! -z "$instVers" ]]; then
        echo " Found version ${instVers} for ${properName}"
        compareVers
    fi
else
    instVers="0"
    notInstalled
fi
}


function compareVers () {

let StepNum=$StepNum+1
echo "[Stage ${StepNum}]: Determining newer version of ${properName}..."

## Print back the actual version strings and the integer comparison strings
echo " Current version of ${properName}:   ${currVers}"
echo " Installed version of ${properName}:     ${instVers}"

## Build 2 new arrays from captured current and installed versions
IFS=. CURRVERS=(${currVers##})
IFS=. INSTVERS=(${instVers##})

## See if they contain the same number of indices
if [[ "${#CURRVERS[@]}" == "${#INSTVERS[@]}" ]]; then

    ## Set a default state condition
    state="SAME"

    ## Loop over each index in each array and compare the numbers
    for ((i=0;i<${#CURRVERS[@]};i++)); do
        if [[ $((10#${CURRVERS[$i]})) -gt $((10#${INSTVERS[$i]})) ]]; then
            state="NEW"
            break
        elif [[ $((10#${CURRVERS[$i]})) -lt $((10#${INSTVERS[$i]})) ]]; then
            state="OLDER"
            break
        else
            continue
        fi
    done
else
    ## If the numbers of indices do not match, run an alternate version comparison algorithm
    echo "Not the same number of indices. Using alternate version comparison..."

    ## Strip the version strings down to pure numbers
    instVers_Int=$( echo "${instVers}" | tr -cd [:digit:] )
    currVers_Int=$( echo "${currVers}" | tr -cd [:digit:] )

    ## Determine which integer string is the longest and assign its character length as a length variable
    ## Modify the shorter integer string to match the length of the longer integer by adding 0's and cut to the same length
    if [ "${#instVers_Int}" -gt "${#currVers_Int}" ]; then
        length="${#instVers_Int}"
        currVers_N=$( printf "%s%0${length}d\n" $(echo "${currVers_Int}") | cut -c -${length} )
        instVers_N="${instVers_Int}"
    elif [ "${#currVers_Int}" -gt "${#instVers_Int}" ]; then
        length="${#currVers_Int}"
        instVers_N=$( printf "%s%0${length}d\n" $(echo "${instVers_Int}") | cut -c -${length} )
        currVers_N="${currVers_Int}"
    elif [ "${#instVers_Int}" -eq "${#currVers_Int}" ]; then
        instVers_N="${instVers_Int}"
        currVers_N="${currVers_Int}"
    fi

    ## Determine the proper state to set the version comparison to
    if [ "${currVers_N}" -gt "${instVers_N}" ]; then
        state="NEW"
    fi

    if [ "${currVers_N}" -eq "${instVers_N}" ]; then
        state="SAME"
    fi

    if [ "${currVers_N}" -lt "${instVers_N}" ]; then
        state="OLDER"
    fi
fi

unset IFS

## Upon exit, we should have a 'state' set we can take the appropriate action on
if [ "$state" == "NEW" ]; then
    echo "[Stage ${StepNum} Result]: Version ${currVers} is newer than the installed version, ${instVers}"
    ## Run the download latest function
    echo "Downloading latest version"
    dlLatest
elif [ "$state" == "SAME" ]; then
    ## Run the up to date function
    upToDate

elif [ "$state" == "OLDER" ]; then
    echo "[Stage ${StepNum} Result]: The installed version (${instVers}) is newer"

    ## Run the newerInstalled function
    newerInstalled
fi
}


function dlLatest () {

## Description: This function is used to download the current, or latest version of the specified product.
## This function gets the download_url string passed to it and uses curl to pull down the update into
## the "/Library/Application Support/ITUpdater/Downloads/" directory

let StepNum=$StepNum+1

if [[ "$updateMode" == "" ]]; then
    updateMode="update"
fi

curl -sf $curlFlag "${download_url}" -o "/Library/Application Support/ITUpdater/Downloads/${properName}_${currVers}.${fileType}"


if [[ -e "/Library/Application Support/ITUpdater/Downloads/${properName}_${currVers}.${fileType}" ]]; then
    echo " Download of ${properName}_${currVers}.${fileType} was successful"
    installPKGUpdate
else
        echo " Download of ${properName}_${currVers}.${fileType} failed. Exiting..."
        exit 1
fi
}


function installPKGUpdate ()
{

## Description: This function is called when the specified app is in a package install format and SelfService is not set.
## It first mounts the disk image, gets the volume name, then proceeds with the installation.

let StepNum=$StepNum+1
echo "[Stage ${StepNum}]: Silently mounting the ${properName} disk image..."

updateVolName=$( /usr/bin/hdiutil attach "/Library/Application Support/ITUpdater/Downloads/${properName}_${currVers}.${fileType}" -nobrowse -noverify -noautoopen 2>&1 | awk -F'[\t]' '/\/Volumes/{ print $NF }' )

if [[ "$?" == "0" ]]; then
    ## Get the package name in the mounted disk image
    updatePKGName=$( ls "$updateVolName" | egrep ".pkg$|.mpkg$" | grep -i "${installerString}" )

    if [[ ! -z "${updatePKGName}" ]]; then
        echo " A package was located in the mounted volume. Getting package details..."

        sleep 1

        echo "Installing the ${properName} pkg update..."


        ## Install the pkg while reading output from installer
        ## Check for the successful upgrade line to set the installation status
        installStatus=1
        while read line; do
            if [[ $( echo "$line" | egrep "The upgrade was successful|The install was successful" ) ]]; then
                installStatus=0
            fi
            done < <(/usr/sbin/installer -pkg "${updateVolName}/${updatePKGName}" -tgt / -allowUntrusted -verboseR 2>&1)

        ## Pause 1 second to allow installation to finish out
        sleep 1

        ## Unmount the volume (use -force flag in case of locked files)
        hdiutil detach "${updateVolName}" -force

        ## Now check the installation results
        if [[ "$installStatus" == "0" ]]; then
            ## Get the new version number
            getNewVers
        else
            ## If we didn't get a status 0 returned from the installation, exit with an error code
            echo "Installation exited with an error code. Install failed..."
            exit_status=1

            cleanUpAction_Failure
        fi
    else
        echo "Could not locate the package in the mounted volume. There was a problem."
        exit_status=2

        cleanUpAction_Failure
    fi
else
    echo "Mounting of the disk image failed. Exit"
    exit_status=3

    cleanUpAction_Failure
fi
}


function getNewVers () {

## Description: This function is called at the end of an installation to check the new version number
## to ensure it is what we expect. The function will call another function based on success or failure results.

let StepNum=$StepNum+1

## Get the new version number from disk to ensure it matches the expected current version
updatedVers=$( /usr/bin/defaults read "${appPath}/Contents/Info.plist" ${CFVers} )

if [[ "${multiInstallString}" == "firefox" ]]; then
    currVers=$(echo "${currVers}" |  tr -cd '[[:digit:]]._-')
fi

## If the assigned application has a versProcessor var assigned, run it to generate a modified version string
if [ ! -z "$versProcessor" ]; then
    updatedVers=$( eval echo "$updatedVers" | $versProcessor )
fi

## Create 2 new arrays from captured current and updated versions
IFS=. CURRVERS=(${currVers##})
IFS=. UPDVERS=(${updatedVers##})

## See if they contain the same number of indices
if [[ "${#CURRVERS[@]}" == "${#UPDVERS[@]}" ]]; then

    ## Set a default poststate condition
    poststate="SUCCESS"

    ## Loop over each index in each array and compare the numbers
    for ((i=0;i<${#CURRVERS[@]};i++)); do
        if [[ "${CURRVERS[i]}" -gt "${UPDVERS[i]}" ]]; then
            poststate="FAILED"
            break
        elif [[ "${CURRVERS[i]}" -lt "${UPDVERS[i]}" ]]; then
            poststate="SUCCESS"
            break
        else
            continue
        fi
    done
else
    ## If the numbers of indices do not match, run an alternate version comparison algorithm
    echo "Not the same number of indices. Using alternate version comparison..."

    ## Strip the version strings down to pure numbers
    updatedVers_Int=$( echo "${updatedVers}" | tr -cd [:digit:] )
    currVers_Int=$( echo "${currVers}" | tr -cd [:digit:] )

    ## Determine which integer string is the longest and assign its character length as a length variable
    ## Modify the shorter integer string to match the length of the longer integer by adding 0's and cut to the same length
    if [ "${#updatedVers_Int}" -gt "${#currVers_Int}" ]; then
        length="${#updatedVers_Int}"
        currVers_N=$( printf "%s%0${length}d\n" $(echo "${currVers_Int}") | cut -c -${length} )
        updatedVers_N="${updatedVers_Int}"
    elif [ "${#currVers_Int}" -gt "${#updatedVers_Int}" ]; then
        length="${#currVers_Int}"
        updatedVers_N=$( printf "%s%0${length}d\n" $(echo "${updatedVers_Int}") | cut -c -${length} )
        currVers_N="${currVers_Int}"
    elif [ "${#updatedVers_Int}" -eq "${#currVers_Int}" ]; then
        updatedVers_N="${updatedVers_Int}"
        currVers_N="${currVers_Int}"
    fi

    ## Determine the proper state to set the version comparison to
    if [ "${currVers_N}" -gt "${updatedVers_N}" ]; then
        echo "[Stage ${StepNum} Result]: Version ${currVers} is newer than the installed version, ${updatedVers}"

        poststate="FAILED"
    fi

    if [ "${currVers_N}" -eq "${updatedVers_N}" ]; then
        echo "[Stage ${StepNum} Result]: The installed version (${instVers}) is current"

        poststate="SUCCESS"
    fi

    if [ "${currVers_N}" -lt "${updatedVers_N}" ]; then
        echo "[Stage ${StepNum} Result]: The installed version (${instVers}) is newer"

        poststate="SUCCESS"
    fi
fi

unset IFS

if [ "$poststate" == "SUCCESS" ]; then
    echo "[Stage ${StepNum}]: Confirmed the new version of ${properName} on disk is now ${updatedVers}..."
    rm -f "/Library/Application Support/ITUpdater/Downloads/${properName}_${currVers}.${fileType}"

    cleanUpAction_Success
fi

if [ "$poststate" == "FAILED" ]; then
    echo "[Stage ${StepNum}]: New version was not updated to equal or greater than ${currVers}. Installation may have failed..."
    rm -f "/Library/Application Support/ITUpdater/Downloads/${properName}_${currVers}.${fileType}"

    cleanUpAction_Failure
fi
}


function cleanUpAction_Success () {

## Description: This function runs on a successful installation of the app or package.
if [ "$updateMode" == "update" ]; then
    echo "[Final Result}]: ${properName} update installation was successful."
elif [ "$updateMode" == "new" ]; then
    echo "[Final Result]: ${properName} installation was successful."
fi

rm -Rf /Library/Application\ Support/ITUpdater/Downloads/*
rm -f "/Library/Application Support/ITUpdater/NoQuit.xml" 2>/dev/null
}


function upToDate () {
## Description: This function is called when the application/plug-in is already up to the current version.
echo -e "[Final Result]: No new version of ${properName} is available for this Mac.\n"
}


function newerInstalled () {
## Description: This function is called when the installed application appears newer than the current version.
echo -e "[Final Result]: The installed version of ${properName} (${instVers}) is already newer than the current release located ($currVers).\n"
}


function notInstalled () {

## Description: This function is called when the target application or plug-in is not installed or not found on the client system
echo " ${properName} is not installed, or was not found on this system"       ##Edited line

updateMode="new"
dlLatest
}


function dlError () {

## Description: This function is called when it was not possible to obtain the correct download location for the application or plug-in.
## It displays this to the end user in a dialog if SelfService mode is enabled.

echo "Could not determine download location for ${properName}"
exit 1
}


function getVersErr () {

## Description: This function is called if we aren't able to gather current version information on the app/plug-in.
## Since the cause of the error can be because the OS is incompatible, or (more rarely) because no active internet connection
## we attempt to check for an active internet connection first, and display appropriate messaging based on the results.

## Check to make sure we have an active internet connection first
curl --connect-timeout 4 --max-time 4 -sfI http://google.com 2>&1 > /dev/null

if [[ "$?" == "0" ]]; then
    echo -e "We have internet access, but couldn't pull version information for ${properName}.\n"
else
    echo -e "Somehow there is no active internet connection on this Mac.\n"
fi
exit 1
}


function cleanUpAction_Failure () {

## Description: This function runs on a failed installation of the app or package.

## Delete the downloaded disk image from /Library/Application Support/ITUpdater/Downloads/
echo "Deleting downloaded disk image..."
rm -f "/Library/Application Support/ITUpdater/Downloads/${properName}_${currVers}.${fileType}"
echo "Installation failure for ${properName} ${currVers}. Exiting..."
exit 1

}


## Start Script

## Create the necessary folder structure for downloads if not present
if [ ! -d "/Library/Application Support/ITUpdater/Downloads/" ]; then
    mkdir -p "/Library/Application Support/ITUpdater/Downloads/"
    chmod -R 775 "/Library/Application Support/ITUpdater"
fi

if [ ! -d "/Library/Application Support/ITUpdater/Reminders/" ]; then
    mkdir -p "/Library/Application Support/ITUpdater/Reminders/"
fi


StepNum=1
getCurrVers