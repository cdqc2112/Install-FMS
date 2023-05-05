#! /bin/echo not-a-standalone-executable
# shellcheck shell=bash
# Dynamic deps
MODULE_MD5SUM_MODULES_SH=e9fb7bd46882b73e0f76bba5d408a7bf
MODULE_MD5SUM_DEFAULTS_SH=70823a848edb840dda3de3c564cc6c13

DOTENV_SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

source "$DOTENV_SCRIPT_DIR/modules.sh" -- dotenv.sh
source "$DOTENV_SCRIPT_DIR/defaults.sh"

DOTENV_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && cd .. &> /dev/null && pwd )"
# Ensure a final slash in dotenv_dir
if [ -z "$DOTENV_DIR" ]; then
    echo "Could not determine working directory"
    exit 1
fi
DOTENV_DIR="${DOTENV_DIR%/}/"

#------------------------
#      Work directory
#------------------------
DEPLOYMENT_TEMPORARY_DIRECTORY=""
# Called automatically on script's end
function finish() {
    if [ "$DEPLOYMENT_TEMPORARY_DIRECTORY" ]; then
        rm -rf -- "$DEPLOYMENT_TEMPORARY_DIRECTORY" || true
    fi
}
trap finish exit

function initTemporaryDirectory() {
    if [ -z "$DEPLOYMENT_TEMPORARY_DIRECTORY" ]; then
        DEPLOYMENT_TEMPORARY_DIRECTORY="`mktemp -d --suffix .fms`"
    fi
}

# Create a temp dir and set the PATH in LAST_TEMP_DIR
# (using output capture would require subshell and break global var + set -euo pipefail)
function createTempDir() {
    initTemporaryDirectory

    LAST_TEMP_DIR="`mktemp -p "$DEPLOYMENT_TEMPORARY_DIRECTORY" -d`"
}

# Create a temp dir and set the PATH in LAST_TEMP_FILE
function createTempFile() {
    local suffix="$1"

    initTemporaryDirectory

    LAST_TEMP_FILE="`mktemp -p "$DEPLOYMENT_TEMPORARY_DIRECTORY" --suffix "$suffix" `"
}

#------------------------
#     Addon management
#------------------------

# shellcheck disable=SC2034
ADDONS="sysperf local"
# initialise arrays to "true", because on some system void arrays throw an error
ADDON_DEFAULT_ENV_FUNCTIONS=(true)
# shellcheck disable=SC2034
ADDON_CREATE_DIRECTORIES_FUNCTIONS=(true)
# shellcheck disable=SC2034
ADDON_ADD_DOCKER_COMPOSE_FUNCTIONS=(true)
# shellcheck disable=SC2034
ADDON_CREATE_REPLICA_DIRECTORIES_FUNCTIONS=(true)
# shellcheck disable=SC2034
ADDON_ADD_HELM_FILE_FUNCTIONS=(true)

function executeInstallFunctions() {
    local callbacks=("$@")
    for callback in "${callbacks[@]}"; do
        $callback || exit 1
    done
}

function importAddons() {
    local ADDON

    # import addons
    for ADDON in ./*.addon; do
        if [ -e "${ADDON}" ]; then
            sig="`head -c 3 "$ADDON" | base64`"
            if [ "$sig" == "H4sI" ]; then
                echo " * Using addon $ADDON"
                # assume addon is tar/zip form.
                createTempDir

                local addon_dir="$LAST_TEMP_DIR"
                tar xzf "$ADDON" -C "$addon_dir"
                # shellcheck disable=SC1090
                builtin source "$addon_dir"/*.addon || exit 1
            else
                echo " * Using live addon $ADDON"
                # import addons functions
                # shellcheck disable=SC1090
                builtin source "${ADDON}" || exit 1
            fi
        fi
    done
}

#-------------------------------
#  Exported variable detection
#-------------------------------

# List all exported env variables in the ENV_KEYS array
function getDeclaredVariables() {
    local id
    ENV_KEYS=()
    for id in ${!A*} ${!B*} ${!C*} ${!D*} ${!E*} ${!F*} ${!G*} \
              ${!H*} ${!I*} ${!J*} ${!K*} ${!L*} ${!M*} ${!N*} \
              ${!O*} ${!P*} ${!Q*} ${!R*} ${!S*} ${!T*} ${!U*} \
              ${!V*} ${!W*} ${!X*} ${!Y*} ${!Z*}; do
        if [ "$id" ]; then
            # Check the variable is actually exported
            if compgen -e -X "!$id" ; then
                ENV_KEYS+=("$id")
            fi
        fi
    done > /dev/null 2>&1
}


# Remove from ENV_KEYS, any variable from SYSTEM_VARIABLES array
SYSTEM_VARIABLES=()
function filterSystemVariables() {
    # Find new environment since beginning
    local NEW_KEYS=()
    local exist
    local id
    local prev
    for id in "${ENV_KEYS[@]+"${ENV_KEYS[@]}"}"; do
        exist=
        for prev in "${SYSTEM_VARIABLES[@]+"${SYSTEM_VARIABLES[@]}"}"; do
            if [ "$prev" = "$id" ]; then
                exist=1
            fi
        done

        if [ -z "$exist" ]; then
            NEW_KEYS+=("$id")
        fi
    done

    ENV_KEYS=("${NEW_KEYS[@]+${NEW_KEYS[@]}}")
}

# Possible secret initialization in the form 'VARIABLE <parameters to createRandomSecretPwd>'
SECRETS_WITH_DEFAULT_INIT=()
# Possible keycloak user to init in the form 'VARIABLE user-id'
KEYCLOAK_USERS_WITH_DEFAULT_INIT=()

# false, force, missing
AUTO_INIT_SECRETS=false

# false/true
AUTO_INIT_KEYCLOAK_USERS=false

# Inidicate if an env id will get auto-initialized (and thus does not require checking)
function willAutoInit() {
    local VARNAME="$1" CURRENT_VALUE="$2" DEFAULT_VALUE="$3"
    local ENTRY ID
    if [ "$AUTO_INIT_SECRETS" != "false" ]; then
        for ENTRY in "${SECRETS_WITH_DEFAULT_INIT[@]}"; do
            ID="${ENTRY%% *}"
            if [ "$ID" = "$VARNAME" ]; then
                if [ "$AUTO_INIT_SECRETS" == "force" ] || [ -z "$CURRENT_VALUE" ] || [[ $CURRENT_VALUE =~ ^\<.*\>$ ]]; then
                    return 0
                fi
            fi
        done
    fi

    if [ "$AUTO_INIT_KEYCLOAK_USERS" = true ]; then
        for ENTRY in "${KEYCLOAK_USERS_WITH_DEFAULT_INIT[@]}"; do
            ID="${ENTRY%% *}"
            if [ "$ID" = "$VARNAME" ]; then
                return 0
            fi

            if [ "${ID}_SECRET" = "$VARNAME" ]; then
                return 0
            fi
        done
    fi

    return 1
}

function loadEnv() {
    local ALLOW_MISSING=
    [ "${1:-}" != --allow-missing ] || ALLOW_MISSING=true

    getDeclaredVariables
    SYSTEM_VARIABLES=("${ENV_KEYS[@]+"${ENV_KEYS[@]}"}")

    if [ ! -e "$DOTENV_DIR/.env" ];then
        if [ -z "$ALLOW_MISSING" ]; then
            echo "Configuration file not found: $DOTENV_DIR/.env - aborting" >&2
            exit 1
        else
            echo "Configuration file not found: $DOTENV_DIR/.env" >&2
            USER_VARIABLES=()
            return 0
        fi
    fi

    set -a
    # shellcheck disable=SC1091
    if ! builtin source "$DOTENV_DIR/.env" ; then
        echo "Invalid environment. Aborting" >&2
        exit 1
    fi
    set +a
    getDeclaredVariables
    filterSystemVariables
    USER_VARIABLES=("${ENV_KEYS[@]+"${ENV_KEYS[@]}"}")
}

ENVIRONMENT_ERRORS=false
ENVIRONMENT_WARNINGS=false
function checkEnvironment() {
    defaultEnv
    defaultSecrets

    local NOFAIL=
    [ "${1:-}" != --no-fail ] || NOFAIL=true

    executeInstallFunctions "${ADDON_DEFAULT_ENV_FUNCTIONS[@]}"

    local RESULT=0
    local VARDEF
    local VARNAME
    local DEFAULT_VALUE
    local CURRENT_VALUE

    local WARNS=""

    for VARDEF in "${DEFAULT_ENV[@]}"; do
        VARNAME="${VARDEF%%=*}"
        DEFAULT_VALUE="${VARDEF#*=}"
        # echo "$VALUE"
        if [ -z "${!VARNAME+x}" ]; then
            if [ "$DEFAULT_VALUE" = "!" ]; then
                if willAutoInit "$VARNAME" "" "$DEFAULT_VALUE"; then
                    continue
                fi

                echo "The env setting $VARNAME is mandatory." >&2
                RESULT=1
                continue
            fi
            export "$VARNAME=$DEFAULT_VALUE"
            CURRENT_VALUE="$DEFAULT_VALUE"
        else
            CURRENT_VALUE="${!VARNAME}"
        fi

        if willAutoInit "$VARNAME" "$CURRENT_VALUE" "$DEFAULT_VALUE"; then
            continue
        fi

        # Additional check goes here (like pattern, ...)
        # Warn when password fields have default values
        case "$VARNAME" in
            *_PASSWORD*|*_PASSWD*)
                if [ "$DEFAULT_VALUE" ] && [ "$DEFAULT_VALUE" = "$CURRENT_VALUE" ]; then
                    WARNS="$WARNS""The env setting $VARNAME is set to the default value. It is recommended to change it at installation."$'\n'
                fi
                ;;
            *_DNS)
                # Ensure dns entries do not have invalid chars
                if [[ "$CURRENT_VALUE" =~ [\<\>\#\%\!] ]]; then
                    echo "The env setting $VARNAME has invalid value."
                    RESULT=1
                    continue
                fi
                ;;
            KEYCLOAK_TOPOLOGY_MASTER_SECURE)
                # Warn on KEYCLOAK_TOPOLOGY_MASTER_SECURE effect
                if [[ "$KEYCLOAK_TOPOLOGY_MASTER_SECURE" == "false" ]]; then
                    WARNS="$WARNS""KEYCLOAK_TOPOLOGY_MASTER_SECURE set to false, this is a security risk. It is recommended to upgrade FG-750s to a supported version and remove this setting from .env"$'\n'
                fi
                ;;
            *_USER_INIT)
                if [ -n "$CURRENT_VALUE" ]; then
                    SECRET_VAR="${VARNAME}"_SECRET

                    if [ -z "${!SECRET_VAR+x}" ] || [ -z "${!SECRET_VAR}" ]; then
                        echo "The docker secret '$SECRET_VAR' is mandatory for user '$VARNAME'."
                        RESULT=1
                        continue
                    fi
                fi
                ;;
        esac
    done

    if [ "$ORCHESTRATOR" != "swarm" ] && [ "$ORCHESTRATOR" != "k8s" ]; then
        echo "Unsupported orchestrator: \"$ORCHESTRATOR\". Please use either swarm or k8s"
        RESULT=1
    fi

    if [ "$WARNS" ]; then
        echo -n "$WARNS" >&2
        ENVIRONMENT_WARNINGS=true
    else
        ENVIRONMENT_WARNINGS=false
    fi
    if [ "$RESULT" != 0 ]; then
        ENVIRONMENT_ERRORS=true
        if [ -z "$NOFAIL" ]; then
            echo "Environnment is invalid, refusing to continue." >&2
            exit 255
        fi
    else
        ENVIRONMENT_ERRORS=false
    fi
}

function warnEnvironment() {
    if [ "$ENVIRONMENT_WARNINGS" != false ]; then
        if [ -t 1 ] && [ -z "`docker stack services -q fms 2> /dev/null`" ]; then
            echo -e "\nHit enter to continue deployment, CTRL+C to abort..." >&2
            read -r
        fi
    fi
}

# Find a variable (first arg) in an array (other args)
function findVar() {
    local searched="$1"
    local v
    shift
    for v in "$@"; do
        # If v is in the form varname=value, keep only the varname part
        v="${v%%=*}"
        if [ "$v" = "$searched" ]; then
            return 0
        fi
    done
    return 1
}

# This function list values that are set to non-default, for migration purpose
function listUsefullEnv() {
    local userVar
    local VARDEF
    local VARNAME
    local DEFAULT_VALUE
    local USELESS=()
    local FOUND_UNKNOWN
    local FOUND_USEFULL
    defaultEnv
    defaultSecrets

    executeInstallFunctions "${ADDON_DEFAULT_ENV_FUNCTIONS[@]}"

    FOUND_USEFULL=false
    # Search first for known variables
    for VARDEF in "${DEFAULT_ENV[@]}"; do
        VARNAME="${VARDEF%%=*}"

        if findVar "$VARNAME" "${USER_VARIABLES[@]+"${USER_VARIABLES[@]}"}"; then
            CURRENT_VALUE="${!VARNAME}"
            DEFAULT_VALUE="${VARDEF#*=}"
            if [ "$DEFAULT_VALUE" != "$CURRENT_VALUE" ]; then
                if [ "$FOUND_USEFULL" = false ]; then
                    FOUND_USEFULL=true
                    printf "\n# The following keys are usefull in the .env file\n\n"
                fi
                if [ "$DEFAULT_VALUE" != "!" ] && [ "$DEFAULT_VALUE" ]; then
                    printf "# Default for %s: %q\n" "$VARNAME" "$DEFAULT_VALUE"
                fi
                printf "%s=%q\n" "$VARNAME" "$CURRENT_VALUE"
            else
                USELESS+=("$VARNAME")
            fi
        fi
    done

    FOUND_UNKNOWN=false
    # Search for unknown variables
    for userVar in "${USER_VARIABLES[@]+"${USER_VARIABLES[@]}"}"; do
        if ! findVar "$userVar" "${DEFAULT_ENV[@]}"; then
            if [ "$FOUND_UNKNOWN" = false ]; then
                FOUND_UNKNOWN=true
                printf "\n# The following keys are present in the .env but do not correspond to any known .env settings\n"
                printf "# They may be typo, keys requiring migration, or belong to a non installed addon\n\n"
            fi
            printf "%s=%q      # Unknown setting\n" "$userVar" "${!userVar}"
        fi
    done

    if [ "${#USELESS[@]}" != 0 ]; then
        printf "\n# The following keys are not required because their current values matches their default values\n"
        printf "# They can safely be removed from the .env file\n\n"
        printf "# - %s\n" "${USELESS[@]}"
    else
        if [ "$FOUND_UNKNOWN" = false ] && [ "$FOUND_USEFULL" = false ]; then
            printf "\n# .env contains no settings\n"
        fi
    fi
}


#------------------------
#     .env modification
#------------------------

# Export a key=value and persist to .env
# Assume .env is in the current directory
function updateDotEnv() {
    local KEY="$1"
    local VALUE="$2"
    local ESCAPED_VALUE

    local currentRight
    currentRight="`sudo stat -L -c '%u:%g' -- "$DOTENV_DIR/.env"`"

    local sudouid="${currentRight%%:*}"
    local sudogid="${currentRight##*:}"

    local AWK=(sudo -u \#"$sudouid" -g \#"${sudogid}" -- awk)

    printf -v ESCAPED_VALUE '%q' "$VALUE"
    # shellcheck disable=SC2016
    "${AWK[@]}" -v "key=$KEY" -v "value=$ESCAPED_VALUE" \
       '
        $0 ~ "^[ \t]*"key"=" {
            $0=key"="value;
            found=1;
        }
        {a[b++]=$0}
        END {
            for(c=0;c<=b;c++) {
              print a[c]>ARGV[1]
            }
            if (!found) { print key"="value>ARGV[1] }
        }' "$DOTENV_DIR/.env"

    export "$KEY=$VALUE"
}

#------------------------
#     YAML string encoded
#------------------------

# Return a value as YAML string encoded
function yamlEscape() {
	local YAML="$1"
	
	YAML=${YAML//\\/\\\\} # \ 
	YAML=${YAML//\"/\\\"} # " 
	YAML=${YAML//   /\\t} # \t (tab)
	YAML=${YAML//^M/\\\r} # \r (carriage return)
	YAML=${YAML//^L/\\\f} # \f (form feed)
	YAML=${YAML//^H/\\\b} # \b (backspace)
	YAML=${YAML//
/\\\n} # \n (newline)
	printf "\"%s\"" "$YAML"
}

function env2yaml() {
	local VAR="$1"
	local VALUE="${!VAR}"
	printf '%s: %s' "`yamlEscape "$VAR"`" "`yamlEscape "$VALUE"`"
}

function generateValueYaml() {
    local id
    local prev
    local exist

    getDeclaredVariables

    # Find new environment since beginning
    NEW_KEYS=()
    for id in "${ENV_KEYS[@]}"; do
        exist=
        for prev in "${SYSTEM_VARIABLES[@]}"; do
            if [ "$prev" = "$id" ]; then
                exist=1
            fi
        done

        if [ -z "$exist" ]; then
            NEW_KEYS+=("$id")
        fi
    done

    # Create the yaml file
    (
        printf "# Autogenerated file - do not modify\n"
        cat helm/values-init.yaml
        [ -f helm/values-local.yaml ] && cat helm/values-local.yaml
        printf "\nenv:\n"
        for k in "${NEW_KEYS[@]}"; do
            printf "  %s\n" "`env2yaml "$k"`"
        done
    ) > helm/values.yaml
}


#------------------------
#     Memory limits
#------------------------
MEMORY_TOTAL_AVAILABLE_MO=$(grep -E '^MemTotal:' /proc/meminfo | awk '{print int($2/1000)}')
# this function defines a variable with the memory limit passed as a parameter (%)
# usage: autoSizeMemoryFromHost MEMORY_LIMIT_CONTAINER_MO 30
function autoSizeMemoryFromHost() {
    local VAR="$1"
    local RATIO="$2"
    if [ -z "${!VAR:-}" ]; then
        local CALC_BUFFER
        typeset -i CALC_BUFFER
        CALC_BUFFER="$MEMORY_TOTAL_AVAILABLE_MO * $RATIO / 100"
        export "$VAR=$CALC_BUFFER"
    fi
}

# this function defines a variable with the JVM memory limit passed as a parameter (%)
# usage: autoSizeJVMHeap MEMORY_LIMIT_CONTAINER_MO MEMORY_LIMIT_CONTAINER_MO_JAVA 70
function autoSizeJVMHeap() {
    local CONTAINER="$1"
    local HEAP="$2"
    local RATIO="$3"
    typeset -i CALC_BUFFER
    CALC_BUFFER="${!CONTAINER} * $RATIO / 100"
    export "$HEAP=$CALC_BUFFER"
}
