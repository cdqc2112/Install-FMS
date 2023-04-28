#! /bin/echo not-a-standalone-executable
# shellcheck shell=bash
#
# This scripts gives access to checked modules loading from scripts
#
# A caller script:
#
# MODULE_INCLUDE_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
# source "$MODULE_INCLUDE_DIR/includes/modules.sh" --

# When sourcing, an optional argument can be passed to indicate the source code of the caller (so it's sha can be checked from dependencies)
# source "$MODULE_INCLUDE_DIR/includes/modules.sh" -- test.sh
#
# Namespace for variable is shared, so every script must have its own MODULE_INCLUDE_DIR directory

function getMd5sum() {
    local MD5SUM
    MD5SUM="`md5sum "$1"`"
    MD5SUM="${MD5SUM%% *}"
    if [ -z "$MD5SUM" ]; then
        exit 255
    fi
    printf "%s" "$MD5SUM"
}

function declareImplicitModuleWithSource() {
    local SCRIPT_NAME="$1"
    local SCRIPT_SOURCE="$2"

    local SCRIPT_ID="${SCRIPT_NAME//./_}"
    SCRIPT_ID="${SCRIPT_ID//-/_}"
    SCRIPT_ID="${SCRIPT_ID^^}"

    local MD5SUM
    MD5SUM="`getMd5sum "$SCRIPT_SOURCE"`"

    local SCRIPT_INCLUSION_KEY="MODULE_LOADED_$SCRIPT_ID"
    local SCRIPT_MD5SUM_KEY="MODULE_MD5SUM_$SCRIPT_ID"

    if [ "${!SCRIPT_MD5SUM_KEY+x}" ]; then
        if [ "$MD5SUM" != "${!SCRIPT_MD5SUM_KEY}" ]; then
            echo "Checksum/version mismatch. Make sure all scripts/addon comes from the same release"
            exit 255
        fi
    fi
    printf -v "$SCRIPT_INCLUSION_KEY" "%s" "$MD5SUM"
}

function initMainModule() {
    declareImplicitModuleWithSource "modules.sh" "${BASH_SOURCE[0]}"

    if [ "$#" -gt 1 ]; then
        # Use BASH_SOURCE[2] because func call appear from caller script
        declareImplicitModuleWithSource "$2" "${BASH_SOURCE[2]}"
    fi
}

# This redefine source as a function that also check MD5 sum
function source() {
    # Check if SHA is defined for scriptname
    local SCRIPT_NAME="${1##*/}"
    local SCRIPT_ID="${SCRIPT_NAME//./_}"
    SCRIPT_ID="${SCRIPT_ID//-/_}"
    SCRIPT_ID="${SCRIPT_ID^^}"

    local SCRIPT_INCLUSION_KEY="MODULE_LOADED_$SCRIPT_ID"
    local SCRIPT_MD5SUM_KEY="MODULE_MD5SUM_$SCRIPT_ID"

    if [ "${!SCRIPT_INCLUSION_KEY+x}" ]; then
        # Script already included
        if [ "${!SCRIPT_MD5SUM_KEY+x}" ]; then
            # Check the key correspond to the one loaded

            if [ "${!SCRIPT_INCLUSION_KEY}" != "${!SCRIPT_MD5SUM_KEY}" ]; then
                echo "Checksum/version mismatch. Make sure all scripts/addon comes from the same release" >&2
                exit 255
            fi
        fi
        return 0
    fi

    if [ ! -f "$1" ]; then
        echo "Missing dependency: $1" >&2
        exit 255
    fi

    local MD5SUM
    MD5SUM="`getMd5sum "$1"`"
    printf -v "$SCRIPT_INCLUSION_KEY" "%s" "$MD5SUM"

    # Check if was already included
    if [ "${!SCRIPT_MD5SUM_KEY+x}" ]; then
        if [ "${!SCRIPT_MD5SUM_KEY}" != "$MD5SUM" ]; then
            echo "Checksum/version mismatch for $1. Make sure all scripts/addon comes from the same release"
            exit 255
        fi
    fi

    builtin source "$1"
}

function checkResourceVersion() {
    # Avoid beeing identified as an actual module usage
    local SCRIPT_NAME="${1##*/}"
    local SCRIPT_ID="${SCRIPT_NAME//./_}"
    SCRIPT_ID="${SCRIPT_ID//-/_}"
    SCRIPT_ID="${SCRIPT_ID^^}"

    local SCRIPT_MD5SUM_KEY="MODULE_MD5SUM_$SCRIPT_ID"

    if [ ! -f "$1" ]; then
        echo "Missing dependency: $1" >&2
        exit 255
    fi

    local MD5SUM
    MD5SUM="`getMd5sum "$1"`"

    if [ "${!SCRIPT_MD5SUM_KEY+x}" ]; then
        if [ "${!SCRIPT_MD5SUM_KEY}" != "$MD5SUM" ]; then
            echo "Checksum/version mismatch for $SCRIPT_NAME. Make sure all scripts/addon/resources comes from the same release" >&2
            exit 255
        fi
    fi
}

# Verify than a module was loaded with the given version
function checkModuleVersion() {
    local SCRIPT_NAME="${1##*/}"
    local SCRIPT_ID="${SCRIPT_NAME//./_}"
    SCRIPT_ID="${SCRIPT_ID//-/_}"
    SCRIPT_ID="${SCRIPT_ID^^}"

    local SCRIPT_INCLUSION_KEY="MODULE_LOADED_$SCRIPT_ID"
    local SCRIPT_MD5SUM_KEY="MODULE_MD5SUM_$SCRIPT_ID"

    if [ "${!SCRIPT_INCLUSION_KEY+x}" ]; then
        # Script already included
        if [ "${!SCRIPT_MD5SUM_KEY+x}" ]; then
            # Check the key correspond to the one loaded

            if [ "${!SCRIPT_INCLUSION_KEY}" != "${!SCRIPT_MD5SUM_KEY}" ]; then
                echo "Checksum/version mismatch. Make sure all scripts/addon comes from the same release" >&2
                exit 255
            fi
        fi
        return 0
    else
        # We arrive here when not invoked from swarm.sh
        # This needs fix elsewhere. Don't check this path for now
        return 0
    fi
}

initMainModule "$@"
