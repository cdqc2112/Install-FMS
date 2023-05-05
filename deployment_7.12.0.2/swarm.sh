#!/bin/bash
# Dynamic deps
MODULE_MD5SUM_MODULES_SH=e9fb7bd46882b73e0f76bba5d408a7bf
MODULE_MD5SUM_DOTENV_SH=6964b1821725902e4d59a53c2c1d0a75
MODULE_MD5SUM_DOCKER_COMPOSE_YML=ce415e6100c94ade31278d3fed398ef1
MODULE_MD5SUM_DOCKER_COMPOSE_REPLICATION_YML=2baa1e04b8701c6f438f093425a53c80
MODULE_MD5SUM_DOCKER_COMPOSE_YML=ce415e6100c94ade31278d3fed398ef1
MODULE_MD5SUM_DOCKER_COMPOSE_REPLICATION_YML=2baa1e04b8701c6f438f093425a53c80

[ "$BASH_VERSION" ] || (echo "Bash required"; exit 1)

set -euo pipefail

SWARM_SH_SOURCE_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
# shellcheck source=./includes/modules.sh
source "$SWARM_SH_SOURCE_DIR/includes/modules.sh" -- swarm.sh
# shellcheck source=./includes/dotenv.sh
source "$SWARM_SH_SOURCE_DIR/includes/dotenv.sh"


umask 022


# Create a directory owner by a user, with a given permission
# Owner is applied recursively if incorrect
# Permission apply only at the directory itself
function createDirectory() {
    local recursive=true

    if [ "$1" == "--no-recursion" ]; then
        recursive=""
        shift
    fi

    local dir="$1" auth="$2" mode="${3:-755}"

    local chownSudoArgs=(--)

    local hasRootSquash=""
    local squashedAuth="$auth"

    if [ -n "$ROOT_SQUASH" ]; then
        hasRootSquash=true

        local sudouid="${auth%%:*}"
        if [ "$sudouid" = 0 ]; then
            sudouid="${ROOT_SQUASH%%:*}"
        fi

        local sudogid="${auth##*:}"
        if [ "$sudogid" = 0 ]; then
            sudogid="${ROOT_SQUASH##*:}"
        fi
        chownSudoArgs=(-- sudo -u \#"$sudouid" -g \#"${sudogid}" --)
        squashedAuth="$sudouid:$sudogid"
    fi


    if sudo [ -e "$dir" ]; then
        local currentRight currentMode
        currentRight="`sudo stat -L -c '%u:%g' -- "$dir"`"
        [ "$currentRight" ]

        if [ "$currentRight" != "$squashedAuth" ]; then
            echo " * Adjusting ownership under $dir ($auth)"
            if [ "$recursive" ]; then
                sudo "${chownSudoArgs[@]}" chown --recursive "$squashedAuth" -- "$dir"
            else
                sudo "${chownSudoArgs[@]}" chown "$squashedAuth" -- "$dir"
            fi
        fi

        currentMode="`sudo stat -L -c '%a' -- "$dir"`"
        [ "$currentMode" ]

        if [ "$currentMode" != "$mode" ]; then
            if [ "$recursive" ]; then
                echo " * Adjusting permission under $dir ($mode)"
                sudo "${chownSudoArgs[@]}" find "$dir" -type d -exec chmod "$mode" {} \;
            else
                echo " * Adjusting permission of $dir ($mode)"
                sudo "${chownSudoArgs[@]}" chmod "$mode" -- "$dir"
            fi
        fi
    else
        local PARENTDIR="${dir%/*}"
        # Ensure the parent directory exists
        local parentMode
        sudo mkdir --parents --mode "755" -- "$PARENTDIR"

        if [ -n "$hasRootSquash" ]; then
            parentMode="`sudo stat -L -c '%a' -- "$PARENTDIR"`"
            sudo chmod 1777 -- "$PARENTDIR"
        fi

        # Only adjust owner recursively (avoid messing with permissions)
        sudo "${chownSudoArgs[@]}" mkdir --parents --mode "$mode" "$dir"

        # Bring back permission to parent
        if [ -n "$hasRootSquash" ]; then
            sudo chmod "$parentMode" -- "$PARENTDIR"
        else
            # Chown is possible only if not using root squash. Sudo was used in root squash mode anyway
            if [ "$recursive" ]; then
                sudo "${chownSudoArgs[@]}" chown --recursive "$squashedAuth" -- "$dir"
            else
                sudo "${chownSudoArgs[@]}" chown "$squashedAuth" -- "$dir"
            fi
        fi

    fi
}

function adjustFileIfExists() {
    local file="$1" auth="$2" mode="$3"
    if sudo [ -e "$file" ]; then
        local stat
        stat="`sudo stat -L -c '%u:%g#%a' -- "$file"`"
        local currentAuth="${stat%#*}"
        local currentMode="${stat#*#}"

        if [ "$currentAuth" != "$auth" ]; then
            echo " * Adjusting ownership of $file ($auth)"
            sudo chown "$auth" -- "$file"
        fi
        if [ "$currentMode" != "$mode" ]; then
            echo " * Adjusting permission at $file ($mode)"
            sudo chmod "$mode" -- "$file"
        fi
    fi
}

function computeSecretUid() {
    local uidVarName="$1"
    local uidGid="$2"

    local uid="${uidGid%%:*}"
    if [ -z "$uid" ]; then
        uid=0
    fi
    export "$uidVarName=$uid"
}


function secret-generator-default() {
    local passwordLength=${1:-16}
    local secretContent
    secretContent="`(tr -dc A-Za-z0-9 </dev/urandom || true > /dev/null 2>&1) | head -c "$passwordLength"`"
    if [ ! ${#secretContent} -eq "${passwordLength}" ]; then
        echo  "Failed to generate $passwordLength long entropy" >&2
        exit 1
    fi
    printf '%s' "$secretContent"
}

function secret-generator-rsync() {
    echo -n 'usr:'
    secret-generator-default "$@"
}

# options:
#  --only-if <VAR>    : test if the variable is true. Ignore secret otherwise
#  --generator func   : use the given generator for the secret (pass the arguments.) Default to secret-generator-default
#  --hidden           : don't display the secret
function createRandomSecretPwd() {
    local envVar="$1"
    shift

    local testvar
    local display=true
    local generator=secret-generator-default
    while [ $# != 0 ]; do
        case "$1" in
            --only-if)
                testvar="$2"
                shift 2
                if [ -z "${!testvar+x}" ] || [ "${!testvar}" != true ]; then
                    # skip this secret
                    return 0
                fi
                ;;
            --generator)
                generator="$2"
                shift 2
                ;;
            --hidden)
                display=false
                shift
                ;;
            *)
                break
                ;;
        esac
    done

    local secretName="$1"
    shift
    local secretContent

    # Make secret_id lowercase for K8S compat
    secretName="${secretName,,}"
    secretName="${secretName//_/-}"

    printf -v secretName "%s-%(%Y%d%m-%H%M%S)T" "$secretName" -1
    secretContent="`$generator "$@"`"

    if [ "${ORCHESTRATOR}" = "k8s" ]; then
        printf '%s' "$secretContent" | kubectl create secret generic "$secretName" --from-file=secret=/dev/stdin > /dev/null
    else
        printf '%s' "$secretContent" | docker secret create "$secretName" - > /dev/null
    fi

    if [ $display = true ]; then
        printf  "created secret %q in %s for %s\n" "$secretContent" "$secretName" "$envVar"
    else
        printf  "created secret %s for %s\n" "$secretName" "$envVar"
    fi

    updateDotEnv "$envVar" "$secretName"
}

function checkSecret() {
    local varName="$1"
    if [ -z "${!varName+x}" ] || [ -z "${!varName}" ]; then
        echo "Missing secret identifier. Please set $varName to a valid docker secret name" >&2
        exit 1
    fi
}

function checkSecretAndAddCompose(){
    local envVarName="$1"
    local service="$2"
    local source="$3"
    local target="$4"
    local uid="$5"
    checkSecret "$envVarName"
    dynamicComposeOverride <<EOF
services:
  $service:
    secrets:
     - { source : $source, target: $target, mode: 0400, uid: "$uid" }
secrets:
  $source: { name: "${!envVarName}", external: true }
EOF
}

function detectDockerVersion() {
    if [ "${ORCHESTRATOR}" != "k8s" ]; then
        DOCKER_VERSION="`docker version --format '{{.Server.Version}}'`"
        if [ -z "$DOCKER_VERSION" ]; then
            echo " * Unknown docker version" >&2
            exit 1
        fi
        echo "Docker server version is $DOCKER_VERSION" >&2
    fi
}

typeset -a ADDITIONAL_COMPOSE=()
typeset -a DYNAMIC_COMPOSE_YAML_FILES=()

# Add a new compose file (as last in the list)
function addComposeFile() {
    local YAML_FILE
    for YAML_FILE in "$@"; do
        ADDITIONAL_COMPOSE=("${ADDITIONAL_COMPOSE[@]+"${ADDITIONAL_COMPOSE[@]}"}" --compose-file "$YAML_FILE")
    done
}

# Copy helm file for running addons
function addHelmDirectory() {
    local ADDON_FILES
    local ADDON_FILE
    ADDON_PATH="$1"

    # Check source files don't overwrite existing files
    mapfile -t ADDON_FILES < <( cd "${ADDON_PATH}" && find . -! -type d -print )
    if [ "${#ADDON_FILES[@]}" != 0 ]; then
        for ADDON_FILE in "${ADDON_FILES[@]}"; do
            ADDON_FILE="${ADDON_FILE#./}"
            if [ -e "${PROCESSED_HELM_OUTPUT_DIR}/${ADDON_FILE}" ]; then
                echo "Conflicting file in addon: ${ADDON_FILE}" >&2
                exit 1
            fi
        done

        # No conflict, copy - incl. directories
        cp -r "${ADDON_PATH}"/* "${PROCESSED_HELM_OUTPUT_DIR}"
    fi
}

function generateDynamicKustomizePatch() {
    local patch_id="$1"
    local patch_file="$2"
    
    local output_patch_file="${PROCESSED_HELM_OUTPUT_DIR}/patchs/${patch_id}-dynamic-patch.yaml"

    if [ -e "$output_patch_file" ]; then
        echo "Patch file conflict: $output_patch_file"
        exit 1
    fi

    helm template fms "${PROCESSED_HELM_OUTPUT_DIR}" -s "${patch_file##"${PROCESSED_HELM_OUTPUT_DIR}"/}" > "$output_patch_file"
}

function generateKustomizePatches() {
    local PATCHS_FILES
    local patch_id
    local patch

    mapfile -t  PATCHS_FILES < <( find "${PROCESSED_HELM_OUTPUT_DIR}/templates/" -type f -name '*patch-template.yaml' -print )
    if [ "${#PATCHS_FILES[@]}" = 0 ]; then
        # No patch to apply
        return 0
    fi

    # Ensure /patchs directory is empty (no pollution from addons)
    mkdir "${PROCESSED_HELM_OUTPUT_DIR}"/patchs

    sed -i "/^addons/c#addons" "${PROCESSED_HELM_OUTPUT_DIR}"/.helmignore #comment the addon in helmignore
    for patch in "${PATCHS_FILES[@]}"; do
        # Derivate an id from full path of patch template
        patch_id="${patch##"${PROCESSED_HELM_OUTPUT_DIR}"/templates/}"
        patch_id="${patch_id//\//-}"

        generateDynamicKustomizePatch "$patch_id" "$patch"
    done

    # Now join all the individual patches into a single one kustomization.yaml
    cat <<EOF > "${PROCESSED_HELM_OUTPUT_DIR}"/templates/global-temp-kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- all.yaml

patchesJson6902:
{{ range \$path, \$_ :=  .Files.Glob  "patchs/**dynamic-patch.yaml" }}
      {{ \$_ := $.Files.Get \$path | fromYaml }}
      {{ \$patch := get \$_ "patchesJson6902" }}
      {{ \$patch | toYaml | nindent 4}}
{{ end }}
EOF
    helm template fms "${PROCESSED_HELM_OUTPUT_DIR}" -s templates/global-temp-kustomization.yaml > "${PROCESSED_HELM_OUTPUT_DIR}"/kustomize/kustomization.yaml
    sed -i "/^#addons/caddons" "${PROCESSED_HELM_OUTPUT_DIR}"/.helmignore #uncomment the addon in helmignore
    rm -rf "${PATCHS_FILES[@]}" "${PROCESSED_HELM_OUTPUT_DIR}"/templates/global-temp-kustomization.yaml "${PROCESSED_HELM_OUTPUT_DIR}"/patchs
}


# Create an anonymous docker-compose override from stdin
function dynamicComposeOverride() {
    createTempFile .yml
    local YAML_FILE="$LAST_TEMP_FILE"

    DYNAMIC_COMPOSE_YAML_FILES=("${DYNAMIC_COMPOSE_YAML_FILES[@]+"${DYNAMIC_COMPOSE_YAML_FILES[@]}"}" "$YAML_FILE")
    (echo "version: '3.7'" && cat) > "$YAML_FILE" || exit 1
    addComposeFile "$YAML_FILE"
}

# Deploy recursively a configuration directory into destination directory
# Installed file have a date set to 2020-01-01, so we can track customer modified files
# Modified files at target are left unchanged
deployConfigurationFiles() {
    local source="$1"
    local destination="$2"
    local file
    local files=()
    local targets=()
    local altered=()
    # This is epoch for 2020-01-01T00:00:00+00:00
    # date -d '2020-01-01T00:00:00+00:00' '+%s'
    local reftime='@1577836800'

    createTempFile .lst
    local SOURCE_LIST_FILE="$LAST_TEMP_FILE"
    createTempFile .lst
    local ALTERED_LIST_FILE="$LAST_TEMP_FILE"

    # Create the list of files to copy
    find "$source" -type f -printf '%P\n' | sort > "$SOURCE_LIST_FILE"

    # Create the list of files not to copy
    sudo find "$destination" -type f -newermt "$reftime" -printf '%P\n' | sort > "$ALTERED_LIST_FILE"

    while IFS= read -r file; do
        files+=("$file")
        targets+=("$destination/$file")
    done < <( comm -23 "$SOURCE_LIST_FILE" "$ALTERED_LIST_FILE" )

    while IFS= read -r file; do
        altered+=("$file")
    done < <(comm -12 "$SOURCE_LIST_FILE" "$ALTERED_LIST_FILE")
    
    if [ "${#altered[@]}" != 0 ]; then
        echo " * Preserving locally modified file(s) in $destination: " "${altered[@]}" >&2
    fi

    if [ "${#files[@]}" != 0 ]; then
        local cfguid=0 cfggid=0
        if [ -n "$ROOT_SQUASH" ]; then
            cfguid="${ROOT_SQUASH%%:*}"
            cfggid="${ROOT_SQUASH##*:}"
        fi

        (cd "$source" && tar -cf - --mtime "$reftime" --owner "$cfguid" --group "$cfggid" "${files[@]}") | sudo tar -C "$destination" -xf - 
    fi
}


function completeEnvironment() {
    local SECRET_TO_INIT SECRET_ID ARGS KEYCLOAK_USER_ENTRY KEYCLOAK_USER_ENTRY_ENV KEYCLOAK_USER_ENTRY_ID KEYCLOAK_SECRET_BASE
    if [ "$AUTO_INIT_SECRETS" != false ]; then
        for SECRET_TO_INIT in "${SECRETS_WITH_DEFAULT_INIT[@]}"; do
            ARGS=()
            # Safe eval since no user controled input here
            eval "ARGS=($SECRET_TO_INIT)"
            SECRET_ID="${ARGS[0]}"

            # Skip initialization of already present variable
            if [ "$AUTO_INIT_SECRETS" = "missing" ] && [ "${!SECRET_ID+x}" ] && [ "${!SECRET_ID}" ] && [[ ! ${!SECRET_ID} =~ ^\<.*\>$ ]]; then
                continue
            fi

            createRandomSecretPwd "${ARGS[@]}"
        done
    fi

    if [ "$AUTO_INIT_KEYCLOAK_USERS" != false ]; then
        # Set users for CI
        for KEYCLOAK_USER_ENTRY in "${KEYCLOAK_USERS_WITH_DEFAULT_INIT[@]}"; do
            ARGS=()
            # Safe eval since no user controled input here
            eval "ARGS=($KEYCLOAK_USER_ENTRY)"
            KEYCLOAK_USER_ENTRY_ENV="${ARGS[0]}"
            KEYCLOAK_USER_ENTRY_ID="${ARGS[1]}"
            KEYCLOAK_SECRET_BASE="${KEYCLOAK_USER_ENTRY_ENV%_USER_INIT}"
            # Prefer - over _
            KEYCLOAK_SECRET_BASE="${KEYCLOAK_SECRET_BASE//_/-}"
            # Prefer lowercase
            KEYCLOAK_SECRET_BASE="${KEYCLOAK_SECRET_BASE,,}"

            createRandomSecretPwd "${KEYCLOAK_USER_ENTRY_ENV}_SECRET" "${KEYCLOAK_SECRET_BASE,,}-passwd"
            updateDotEnv "$KEYCLOAK_USER_ENTRY_ENV" "$KEYCLOAK_USER_ENTRY_ID"
        done
    fi
}


function usage() {
    echo "Usage :"
    echo "./swarm.sh [--random-db-pwd-secret] [--fill-secrets] [--no-deploy] [--] (...deploy arguments)"
    echo "  Deploy the fms solution. Additional arguments can be passed to docker stack deploy command"
    echo "    --fill-secrets          automatically generate required secret not already defined in env"
    echo "    --init-iam-users        generate password secrets for default IAM accounts (assumes users don't already exist)"
    echo "    --no-deploy             Prepare filesystem for fms deployment, but does not actually deploy it"
    echo "    --check-env             List the settings that are missing / invalid"
    echo "    --list-usefull-env      List the settings that actually differs from defaults"
    echo ""
    echo "./swarm.sh image-pull"
    echo "  Pull all the docker image required for the current configuration"
    echo ""
    echo "./swarm.sh image-save [-d destination]"
    echo "  Pull and save all the docker image required for the current configuration"
    echo "    -d destination    Write the image files in the destination directory"
    exit 255
}

ADDONS="sysperf local"

# Abort on unset variables
set -euo pipefail

if [ $# != 0 ] && [[ "$1" = "image-pull" || "$1" = "image-save" || "$1" = "get-images" ]]; then
    MODE="$1"
    DESTINATION="./"
    shift
    while [ $# != 0 ]; do
        case "$1" in
            -d)
                if [ "$MODE" != "image-save" ]; then
                    usage
                fi
                shift
                if [ "$#" = 0 ]; then
                    usage
                fi
                DESTINATION="$1/"
                shift
                ;;
            *)
                usage
                ;;
        esac

    done

    importAddons
    loadEnv --allow-missing
    checkEnvironment --no-fail

    executeInstallFunctions "${ADDON_ADD_DOCKER_COMPOSE_FUNCTIONS[@]}"

    checkResourceVersion "$SWARM_SH_SOURCE_DIR/docker-compose.yml"
    if [ -f "$SWARM_SH_SOURCE_DIR/docker-compose-replication.yml" ]; then
        checkResourceVersion "$SWARM_SH_SOURCE_DIR/docker-compose-replication.yml"
    fi

    mapfile -t IMAGES < <( ( cat ./docker-compose.yml;
            for ADDON in replication $ADDONS; do
                if [ -f "./docker-compose-$ADDON.yml" ]; then
                    cat "./docker-compose-$ADDON.yml"
                fi
            done;
            for ADDON in replication "${ADDITIONAL_COMPOSE[@]+"${ADDITIONAL_COMPOSE[@]}"}"; do
                if [ -f "$ADDON" ]; then
                    cat "$ADDON"
                fi
            done ) |
            sed -n 's/^ *image:[ "]*\([^"]*\)"*/\1/p' | sort -u )

    if [ "$MODE" = "get-images" ]; then
        printf '%s\n' "${IMAGES[@]}"
    else
        TASKS=()

        echo "Fetching ${#IMAGES[@]} images" >&2
        for IMAGE in "${IMAGES[@]}"; do
            (
                docker pull -q "$IMAGE" || exit 1

                if [ "$MODE" = "image-save" ]; then
                    FILE="${IMAGE//\//-}"
                    FILE="$DESTINATION${FILE//:/_}.tar"
                    docker save -o "$FILE" "$IMAGE" || exit 1
                    echo "Saved $FILE" >&2
                else
                    echo "Pulled $IMAGE" >&2
                fi
            ) &
            TASKS+=($!)
        done

        error=0
        for task in "${TASKS[@]}"; do
            if ! wait "$task"; then
                error=1
            fi
        done

        if [ $error == 1 ]; then
            exit 1
        fi
    fi

    exit 0
fi

if [ "$#" != 0 ]; then
    # Handle option that don't lead to deployment
    case "$1" in
        --help)
            usage
            ;;
        --check-env)
            [ "$#" = 1 ] || usage

            importAddons
            loadEnv --allow-missing
            checkEnvironment --no-fail
            if [ "$ENVIRONMENT_ERRORS" = true ]; then
                echo "=> Environment is incomplete" >&2
            else
                echo "=> Environement is OK" >&2
            fi
            exit 0
            ;;

        --list-usefull-env)
            [ "$#" = 1 ] || usage
            importAddons
            loadEnv --allow-missing
            listUsefullEnv
            exit 0
            ;;
    esac
fi

importAddons

loadEnv

SKIP_DEPLOY=false

while [ "$#" != 0 ]; do
    case "$1" in
        --random-db-pwd-secret)
            # existing deployment compatibility
            shift
            AUTO_INIT_SECRETS=force
            AUTO_INIT_KEYCLOAK_USERS=true
            ;;
        --fill-secrets)
            shift
            AUTO_INIT_SECRETS=missing
            ;;
        --init-iam-users)
            shift
            AUTO_INIT_KEYCLOAK_USERS=true
            ;;
        --no-deploy)
            shift
            SKIP_DEPLOY=true
            ;;
        *)
            if [ "$SKIP_DEPLOY" = true ]; then
                usage
            fi
            break
            ;;
    esac
done

checkEnvironment
warnEnvironment

detectDockerVersion

completeEnvironment

# addons docker-compose
executeInstallFunctions "${ADDON_ADD_DOCKER_COMPOSE_FUNCTIONS[@]}"

checkResourceVersion "$SWARM_SH_SOURCE_DIR/docker-compose.yml"
if [ "$REPLICATION_ENABLED" == "true" ]; then
    checkResourceVersion "$SWARM_SH_SOURCE_DIR/docker-compose-replication.yml"
fi

function supportNginxAsNonRoot() {
    local service="$1"
    local uidGidVarName="$2"
    local uidGidVarNameEffective="$3"
    local uidGidTarget="$4"
    local uidGid="${!uidGidVarName}"

    export "$uidGidVarNameEffective="
    
    # Checking ip_unprivileged_port_start support for nginx as non root
    if [ "$uidGid" != "0:0" ]; then
        export "$uidGidVarNameEffective="
        # Check support for ip_unprivileged_port_start, then root
        if sudo [ ! -f /proc/sys/net/ipv4/ip_unprivileged_port_start ]; then
            echo " * $service will partially require root access due to kernel/docker version combination."
            export "$uidGidVarNameEffective=$uidGidTarget"
            export "$uidGidVarName=0:0"
        else
            dynamicComposeOverride <<EOF
services:
  $service:
    sysctls:
      # Binding privilege is required for SSL (listening an unprivileged port does not work because port redirection do not work from inside stack)
      - net.ipv4.ip_unprivileged_port_start=443
EOF
        fi
    else
        export "$uidGidVarNameEffective=$uidGidTarget"
    fi
}

supportNginxAsNonRoot proxy PROXY_UID_GID PROXY_EFFECTIVE_UID_GID "$PROXY_UID_GID"

checkSecret 'PROXY_SESSION_SECRET'
computeSecretUid PROXY_SECRETS_UID "${PROXY_EFFECTIVE_UID_GID:-${PROXY_UID_GID}}"
checkSecret 'TOPOLOGY_DB_PASSWORD_SECRET'
computeSecretUid TOPOLOGY_API_UID "${TOPOLOGY_API_UID_GID}"
checkSecret 'KEYCLOAK_DB_PASSWORD_SECRET'
computeSecretUid KEYCLOAK_UID "${KEYCLOAK_UID_GID}"
checkSecret 'MONGO_PASSWORD_MEASURE_SECRET'
computeSecretUid MEASUREMENT_FILE_UID "${MEASUREMENT_FILE_UID_GID}"
computeSecretUid MEASUREMENT_UID "${MEASUREMENT_UID_GID}"
checkSecret 'MONGO_PASSWORD_ALARMING_SECRET'
computeSecretUid ALARMING_UID "${ALARMING_UID_GID}"
checkSecret 'MONGO_PASSWORD_ALARMING_METRICS_SECRET'
computeSecretUid ALARMING_METRICS_PROXY_UID  "${ALARMING_METRICS_PROXY_UID_GID}"
checkSecret 'CONDUCTOR_DB_PASSWORD_SECRET'
computeSecretUid CONDUCTOR_SECRETS_UID  "${CONDUCTOR_SERVER_UID_GID}"
checkSecret 'RTU_VERSION_CONTROLLER_TOKEN_SECRET'
computeSecretUid RTU_VERSION_CONTROLLER_UID "${RTU_VERSION_CONTROLLER_UID_GID}"
checkSecret 'JOLOKIA_PASSWORD_SECRET'
checkSecret 'RTU_BROKER_ADMIN_PASSWORD_SECRET'
computeSecretUid RTU_BROKER_UID "${RTU_BROKER_UID_GID}"
computeSecretUid MEASUREMENT_HANDLER_UID "${MEASUREMENT_HANDLER_UID_GID}"
computeSecretUid RTU_API_GATEWAY_UID "${RTU_API_GATEWAY_UID_GID}"
checkSecret 'IAM_CLIENT_SECRET'
checkSecret 'MONGO_PASSWORD_RTU_API_GATEWAY_SECRET'
computeSecretUid RTU_API_GATEWAY_UID  "${RTU_API_GATEWAY_UID_GID}"


# Expose RTU Broker Ports

if [ "$EXPOSE_DEV_PORT" = "true" ]; then
    dynamicComposeOverride <<EOF
services:
  rtu-broker:
    ports:     
      - mode: host # Stomp support
        protocol: tcp
        published: 61613
        target: 61613
      - mode: host # JMS 
        protocol: tcp
        published: 61616
        target: 61616
EOF
fi

if [ -n "${SERVER_CERT_SECRET:-}${SERVER_CERT_KEY_SECRET:-}" ]; then
    computeSecretUid PROXY_UID "${PROXY_EFFECTIVE_UID_GID:-${PROXY_UID_GID}}"
    checkSecretAndAddCompose SERVER_CERT_SECRET proxy single_cert /opt/fgms/cer/single.cert "$PROXY_UID"
    checkSecretAndAddCompose SERVER_CERT_KEY_SECRET proxy single_key /opt/fgms/cer/single.key "$PROXY_UID"
    if [ -z "${RTUPROXY_ACTIVE+x}" ]; then
        checkSecretAndAddCompose SERVER_CERT_SECRET rtu-broker single_cert /opt/fgms/cer/single.cert "$RTU_BROKER_UID"
        checkSecretAndAddCompose SERVER_CERT_KEY_SECRET rtu-broker single_key /opt/fgms/cer/single.key "$RTU_BROKER_UID"
    fi
fi


if [ -n "${FGMS_TRUSTSTORE_SECRET:-}${FGMS_TRUSTSTORE_PASSWD_SECRET:-}" ]; then
    computeSecretUid TOPOLOGY_API_UID "${TOPOLOGY_API_UID_GID}"
    checkSecretAndAddCompose FGMS_TRUSTSTORE_SECRET keycloak fgms_truststore /opt/fgms/cer/fgmstruststore.jks "1000"
    checkSecretAndAddCompose FGMS_TRUSTSTORE_PASSWD_SECRET keycloak fgms_truststore_passwd /opt/fgms/cer/fgms_truststore_passwd "1000"
    checkSecretAndAddCompose FGMS_TRUSTSTORE_SECRET topology-api fgms_truststore /opt/fgms/cer/fgmstruststore.jks "$TOPOLOGY_API_UID"
    checkSecretAndAddCompose FGMS_TRUSTSTORE_PASSWD_SECRET topology-api fgms_truststore_passwd /opt/fgms/cer/fgms_truststore_passwd "$TOPOLOGY_API_UID"
fi

if [ -n "${RTU_SSL_AUTH_TRUSTSTORE_FILE_SECRET:-}${RTU_SSL_AUTH_TRUSTSTORE_PASSWD_SECRET:-}" ]; then
    checkSecretAndAddCompose RTU_SSL_AUTH_TRUSTSTORE_FILE_SECRET rtu-broker fgms_rtu_truststore /opt/fgms/cer/fgms_rtu_truststore "$RTU_BROKER_UID"
    checkSecretAndAddCompose RTU_SSL_AUTH_TRUSTSTORE_PASSWD_SECRET rtu-broker fgms_rtu_truststore_passwd /opt/fgms/cer/fgms_rtu_truststore_passwd "$RTU_BROKER_UID"
fi

if [ -n "${ALARMING_CONFIG_EMAIL_FILE_SECRET:-}" ]; then
    checkSecretAndAddCompose ALARMING_CONFIG_EMAIL_FILE_SECRET alarming email-notification-config.json /run/secrets/email-notification-config.json "$ALARMING_UID"
fi
if [ -n "${ALARMING_CONFIG_SNMP_FILE_SECRET:-}" ]; then
    checkSecretAndAddCompose ALARMING_CONFIG_SNMP_FILE_SECRET alarming snmp-notification-config.json /run/secrets/snmp-notification-config.json "$ALARMING_UID"
fi

if [ -n "${EST_PASSWORD_SECRET:-}${EST_CLIENT_KEY_SECRET:-}${EST_CLIENT_CER_SECRET:-}${EST_CLIENT_CACER_SECRET:-}" ] && [ -z "${RTUPROXY_ACTIVE+x}" ]; then
    computeSecretUid EST_SECRETS_UID "${PROXY_EFFECTIVE_UID_GID:-${PROXY_UID_GID}}"
    checkSecretAndAddCompose EST_PASSWORD_SECRET proxy est_password /est/htpasswd "$EST_SECRETS_UID"
    checkSecretAndAddCompose EST_CLIENT_KEY_SECRET proxy est_client_key /est/client_key "$EST_SECRETS_UID"
    checkSecretAndAddCompose EST_CLIENT_CER_SECRET proxy est_client_cer /est/client_cer "$EST_SECRETS_UID"
    checkSecretAndAddCompose EST_CLIENT_CACER_SECRET proxy est_client_cacer /est/public/cacerts "$EST_SECRETS_UID"
    dynamicComposeOverride <<"EOF"
services:
  proxy:
    environment:
      - EST_SUPPORT=true
EOF
fi


function keycloakUserInit() {
    local ENVNAME="$1" SECRET_NAME="$2" SECRET_PATH="$3"
    if [ "${!ENVNAME:-}" ]; then
        checkSecretAndAddCompose "${ENVNAME}_SECRET" keycloak "${SECRET_NAME}" "${SECRET_PATH}" "$KEYCLOAK_UID"
    fi
}

keycloakUserInit KEYCLOAK_MASTER_ADMIN_USER_INIT keycloak_master_pwd /run/secrets/keycloak_master_pwd
keycloakUserInit KEYCLOAK_FIBER_ADMIN_USER_INIT keycloak_pwd /run/secrets/keycloak_pwd
keycloakUserInit KEYCLOAK_FIBER_TEST_USER_INIT keycloak_test_pwd /run/secrets/keycloak_test_pwd

# Pass keycloak admin secret to topology only if topology/keycloak secure mode is off
if [[ "$KEYCLOAK_TOPOLOGY_MASTER_SECURE" != "true" ]]; then
    checkSecretAndAddCompose KEYCLOAK_MASTER_ADMIN_USER_INIT_SECRET topology-api keycloak_master_pwd /run/secrets/keycloak_master_pwd "${TOPOLOGY_API_UID}"
fi

# Persistent data
createDirectory --no-recursion "${ROOT_PATH}${PERSISTENT_DATA_DIR}" "0:0" 755
createDirectory "${ROOT_PATH}${PERSISTENT_DATA_DIR}${RTU_BROKER}" "$RTU_BROKER_UID_GID" 700
createDirectory "${ROOT_PATH}${PERSISTENT_DATA_DIR}${FILE_DATA}" "$MEASUREMENT_FILE_UID_GID" 700
createDirectory "${ROOT_PATH}${PERSISTENT_DATA_DIR}${SECURITY_DATA}" 70:70 700
createDirectory "${ROOT_PATH}${PERSISTENT_DATA_DIR}${TOPOLOGY_DATA}" 70:70 700
createDirectory "${ROOT_PATH}${PERSISTENT_DATA_DIR}${CONDUCTOR_DATA}" 70:70 700
createDirectory "${ROOT_PATH}${PERSISTENT_DATA_DIR}${MEASUREMENT_DATA}" 999:0 700
createDirectory "${ROOT_PATH}${PERSISTENT_DATA_DIR}${ALARM_DATA}" 999:0 700
createDirectory "${ROOT_PATH}${PERSISTENT_DATA_DIR}${ALARMING_METRICS_DATA}" "$ALARMING_METRICS_UID_GID" 700
createDirectory --no-recursion "${ROOT_PATH}${PERSISTENT_DATA_DIR}${DISTRIBUTION_DATA}" 0:0 755
createDirectory "${ROOT_PATH}${PERSISTENT_DATA_DIR}${DISTRIBUTION_DATA}/FG750/latest" 0:0 755
createDirectory "${ROOT_PATH}${PERSISTENT_DATA_DIR}${DISTRIBUTION_DATA}/FG750/forceUpdate" 0:0 755
createDirectory "${ROOT_PATH}${PERSISTENT_DATA_DIR}${DISTRIBUTION_DATA}/RTU-2/latest" 0:0 755
createDirectory "${ROOT_PATH}${PERSISTENT_DATA_DIR}${DISTRIBUTION_DATA}/RTU-2/forceUpdate" 0:0 755
createDirectory "${ROOT_PATH}${PERSISTENT_DATA_DIR}${DISTRIBUTION_DATA}/OTH-7000/latest" 0:0 755
createDirectory "${ROOT_PATH}${PERSISTENT_DATA_DIR}${DISTRIBUTION_DATA}/OTH-7000/forceUpdate" 0:0 755
createDirectory "${ROOT_PATH}${PERSISTENT_DATA_DIR}${DISTRIBUTION_DATA}/OTAU-9150/latest" 0:0 755
createDirectory "${ROOT_PATH}${PERSISTENT_DATA_DIR}${DISTRIBUTION_DATA}/OTAU-9150/forceUpdate" 0:0 755


createDirectory "${ROOT_PATH}${PERSISTENT_DATA_DIR}${CONDUCTOR_ELASTICSEARCH}" "${CONDUCTOR_ELASTICSEARCH_UID_GID}" 700
createDirectory "${ROOT_PATH}${PERSISTENT_DATA_DIR}${CONDUCTOR_CEREBRO}" "${CONDUCTOR_CEREBRO_UID_GID}" 700
createDirectory "${ROOT_PATH}${PERSISTENT_DATA_DIR}${RTU_VERSION_CONTROLLER}" "$RTU_VERSION_CONTROLLER_UID_GID" 700
createDirectory "${ROOT_PATH}${PERSISTENT_DATA_DIR}${METRIC_DATA}" 999:0 700
createDirectory "${ROOT_PATH}${PERSISTENT_DATA_DIR}${RTU_API_GATEWAY}" 999:0 700

createDirectory "${ROOT_PATH}${PERSISTENT_DATA_DIR}${VICTORIA_METRICS_DATA}" "${VICTORIA_METRICS_UID_GID}" 700

# Logs
createDirectory "${ROOT_PATH}${LOG_DIR}${RTU_BROKER}" "$RTU_BROKER_UID_GID" "$LOG_DIR_MOD"
createDirectory "${ROOT_PATH}${LOG_DIR}${PROXY_LOG}" "${PROXY_EFFECTIVE_UID_GID:-${PROXY_UID_GID}}" "$LOG_DIR_MOD"
createDirectory "${ROOT_PATH}${LOG_DIR}${TOPOLOGY_LOG}" "${TOPOLOGY_API_UID_GID}" "$LOG_DIR_MOD"
createDirectory "${ROOT_PATH}${LOG_DIR}${MEASUREMENT_HANDLER_LOG}" "$MEASUREMENT_HANDLER_UID_GID" "$LOG_DIR_MOD"
createDirectory "${ROOT_PATH}${LOG_DIR}${ALARM_LOG}" "${ALARMING_UID_GID:-1008:1008}" "$LOG_DIR_MOD"
createDirectory "${ROOT_PATH}${LOG_DIR}${RTU_VERSION_CONTROLLER}" "$RTU_VERSION_CONTROLLER_UID_GID" "$LOG_DIR_MOD"
createDirectory "${ROOT_PATH}${LOG_DIR}${FILE_REPLICATION_LOG}" 0:0 "$LOG_DIR_MOD"
if [ -z "${RTUPROXY_ACTIVE+x}" ]; then
    createDirectory "${ROOT_PATH}${LOG_DIR}${RTU_UPDATES_LOGS}" "${PROXY_EFFECTIVE_UID_GID:-${PROXY_UID_GID}}" "$LOG_DIR_MOD"
    createDirectory "${ROOT_PATH}${LOG_DIR}${RTU_GENERAL_LOGS}" "${PROXY_EFFECTIVE_UID_GID:-${PROXY_UID_GID}}" "$LOG_DIR_MOD"
fi
createDirectory "${ROOT_PATH}${LOG_DIR}${ALARMING_METRICS_PROXY_LOG}" "${ALARMING_METRICS_PROXY_UID_GID}" "$LOG_DIR_MOD"
createDirectory "${ROOT_PATH}${LOG_DIR}${RTU_API_GATEWAY}" "${RTU_API_GATEWAY_UID_GID}" "$LOG_DIR_MOD"
createDirectory "${ROOT_PATH}${LOG_DIR}${CONDUCTOR_CEREBRO}" "${CONDUCTOR_CEREBRO_UID_GID}" "$LOG_DIR_MOD"

# Custom configuration
createDirectory "${ROOT_PATH}${CONFIG}${TOPOLOGY_DATA}" 0:0 755
createDirectory "${ROOT_PATH}${CONFIG}${ALARM_DATA}" 0:0 755
createDirectory "${ROOT_PATH}${CONFIG}${ALARMING_METRICS_DATA}" 0:0 755
createDirectory "${ROOT_PATH}${CONFIG}${TOPOLOGY_UI_DATA}" 0:0 755
createDirectory "${ROOT_PATH}${CONFIG}${RTU_VERSION_CONTROLLER}" 0:0 755
createDirectory "${ROOT_PATH}${CONFIG}${KEYCLOAK_CONFIG}" 0:0 755

if [ -n "$ROOT_SQUASH" ]; then
    PGSUDO=(sudo -- sudo -u \#"70" -g \#"70" --)
    # Ensure sudo is working
    "${PGSUDO[@]}" /bin/true
else
    PGSUDO=(sudo --)
fi

if "${PGSUDO[@]}" [ -d "${ROOT_PATH}${PERSISTENT_DATA_DIR}${SECURITY_DATA}" ] && "${PGSUDO[@]}" [ ! -d "${ROOT_PATH}${PERSISTENT_DATA_DIR}${SECURITY_DATA}/v9.5" ] && "${PGSUDO[@]}" [ ! -d "${ROOT_PATH}${PERSISTENT_DATA_DIR}${SECURITY_DATA}/v13" ] && [ "$("${PGSUDO[@]}" ls -A "${ROOT_PATH}${PERSISTENT_DATA_DIR}${SECURITY_DATA}/")" ]; then
    if "${PGSUDO[@]}" [ -d "${ROOT_PATH}${PERSISTENT_DATA_DIR}${SECURITY_DATA}/tmp" ]; then
        "${PGSUDO[@]}" mv -- "${ROOT_PATH}${PERSISTENT_DATA_DIR}${SECURITY_DATA}/tmp" "${ROOT_PATH}${PERSISTENT_DATA_DIR}${SECURITY_DATA}/v9.5"
    else
        ("${PGSUDO[@]}" mv -- "${ROOT_PATH}${PERSISTENT_DATA_DIR}${SECURITY_DATA}" "${ROOT_PATH}${PERSISTENT_DATA_DIR}${SECURITY_DATA}95" &&
          "${PGSUDO[@]}" mkdir --parents --mode 700 -- "${ROOT_PATH}${PERSISTENT_DATA_DIR}${SECURITY_DATA}" &&
          "${PGSUDO[@]}" chown 70:70 -- "${ROOT_PATH}${PERSISTENT_DATA_DIR}${SECURITY_DATA}" &&
          "${PGSUDO[@]}" mv -- "${ROOT_PATH}${PERSISTENT_DATA_DIR}${SECURITY_DATA}95" "${ROOT_PATH}${PERSISTENT_DATA_DIR}${SECURITY_DATA}/v9.5") ||
        (echo "Failed during 'Security' data transit to v9.5 folder. The data folder has been renamed to ${ROOT_PATH}${PERSISTENT_DATA_DIR}${SECURITY_DATA}95. You shall run : ";
          echo "sudo mkdir --parents -- '${ROOT_PATH}${PERSISTENT_DATA_DIR}${SECURITY_DATA}'";
          echo "sudo mv -- '${ROOT_PATH}${PERSISTENT_DATA_DIR}${SECURITY_DATA}95' '${ROOT_PATH}${PERSISTENT_DATA_DIR}${SECURITY_DATA}/v9.5'")
    fi
fi

if "${PGSUDO[@]}" [ -d "${ROOT_PATH}${PERSISTENT_DATA_DIR}${TOPOLOGY_DATA}" ] && "${PGSUDO[@]}" [ ! -d "${ROOT_PATH}${PERSISTENT_DATA_DIR}${TOPOLOGY_DATA}/v9.5" ] && "${PGSUDO[@]}" [ ! -d "${ROOT_PATH}${PERSISTENT_DATA_DIR}${TOPOLOGY_DATA}/v13" ] && [ "$("${PGSUDO[@]}" ls -A "${ROOT_PATH}${PERSISTENT_DATA_DIR}${TOPOLOGY_DATA}/")" ]; then
    ("${PGSUDO[@]}" mv -- "${ROOT_PATH}${PERSISTENT_DATA_DIR}${TOPOLOGY_DATA}" "${ROOT_PATH}${PERSISTENT_DATA_DIR}${TOPOLOGY_DATA}95" &&
      "${PGSUDO[@]}" mkdir --parents --mode 700 -- "${ROOT_PATH}${PERSISTENT_DATA_DIR}${TOPOLOGY_DATA}" &&
      "${PGSUDO[@]}" chown 70:70 -- "${ROOT_PATH}${PERSISTENT_DATA_DIR}${TOPOLOGY_DATA}" &&
      "${PGSUDO[@]}" mv -- "${ROOT_PATH}${PERSISTENT_DATA_DIR}${TOPOLOGY_DATA}95" "${ROOT_PATH}${PERSISTENT_DATA_DIR}${TOPOLOGY_DATA}/v9.5") ||
    (echo "Failed during 'Topology' data transit to v9.5 folder. The data folder has been renamed to ${ROOT_PATH}${PERSISTENT_DATA_DIR}${TOPOLOGY_DATA}95. You shall run : ";
        echo "sudo mkdir --parents -- '${ROOT_PATH}${PERSISTENT_DATA_DIR}${TOPOLOGY_DATA}'";
        echo "sudo mv -- '${ROOT_PATH}${PERSISTENT_DATA_DIR}${TOPOLOGY_DATA}95' '${ROOT_PATH}${PERSISTENT_DATA_DIR}${TOPOLOGY_DATA}/v9.5'")
fi


if [ "$REPLICATION_ENABLED" == "true" ]; then
    addComposeFile "docker-compose-replication.yml"
    computeSecretUid CONFIG_REPLICATION_UID "$CONFIG_REPLICATION_UID_GID"
    computeSecretUid VICTORIA_METRICS_UID "$VICTORIA_METRICS_UID_GID"
    checkSecret MONGO_MEASURE_REPLICATION_TOKEN_SECRET
    checkSecret MONGO_ALARM_REPLICATION_TOKEN_SECRET
    checkSecret FILE_REPLICATION_SECRET
fi

# this variable is override when rtu-proxy is used
export RTUBROKER_NODE_CONSTRAINT=node.labels.endpoints==true
export PROXY_NODE_CONSTRAINT=node.labels.endpoints==true

# Memory limits
# topology
autoSizeMemoryFromHost MEMORY_LIMIT_TOPOLOGYAPI_MO 30
autoSizeJVMHeap MEMORY_LIMIT_TOPOLOGYAPI_MO MEMORY_LIMIT_TOPOLOGYAPI_MO_JAVA 70
# rtu-broker
autoSizeMemoryFromHost MEMORY_LIMIT_RTUBROKER_MO 30
autoSizeJVMHeap MEMORY_LIMIT_RTUBROKER_MO MEMORY_LIMIT_RTUBROKER_MO_JAVA 70
# measurement-handler
autoSizeMemoryFromHost MEMORY_LIMIT_MEASHANDLER_MO 30
autoSizeJVMHeap MEMORY_LIMIT_MEASHANDLER_MO MEMORY_LIMIT_MEASHANDLER_MO_JAVA 70
# alarming-metrics
autoSizeMemoryFromHost MEMORY_LIMIT_ALARMINGMETRICS_MO 30

# addons directories
executeInstallFunctions "${ADDON_CREATE_DIRECTORIES_FUNCTIONS[@]}"

for ADDON in $ADDONS; do
    if [ -f "docker-compose-$ADDON.yml" ]; then
        addComposeFile "docker-compose-$ADDON.yml"
    fi
done

if [ "$ORCHESTRATOR" = "k8s" ]; then
    export RTUBROKER_NODE_CONSTRAINT='role: "primary"'
    export PROXY_NODE_CONSTRAINT='role: "primary"'
    echo " * generating helm Values.yaml"
    generateValueYaml
fi

if [ "$ORCHESTRATOR" = "k8s" ]; then
    createTempDir
    PROCESSED_HELM_OUTPUT_DIR="$LAST_TEMP_DIR"
    cp -r helm/. "${PROCESSED_HELM_OUTPUT_DIR}"
    
    executeInstallFunctions "${ADDON_ADD_HELM_FILE_FUNCTIONS[@]}"
    generateKustomizePatches

    if [ "$SKIP_DEPLOY" = true ]; then
        cp -r "${PROCESSED_HELM_OUTPUT_DIR}/." helm-out
        echo " * Skipped stack deployment."
        echo "Helm chart is available in helm-out/ and can be deployed with the following command"
        echo "helm upgrade fms helm-out  --post-renderer=helm-out/kustomize/kustomize.sh --install --force"
        exit 0
    else
        echo " * Running helm"
        helm upgrade fms "${PROCESSED_HELM_OUTPUT_DIR}"  --post-renderer="${PROCESSED_HELM_OUTPUT_DIR}"/kustomize/kustomize.sh  --install --force
    fi
    
else
    if [ "$SKIP_DEPLOY" = true ]; then
        echo " * Skipped stack deployment"
        exit 0
    fi

    # Default to resolve-image change to speed up updates
    if [ "$#" != 0 ]; then
        if [ "$1" = "--" ]; then
            shift
        fi
    else
        set -- --resolve-image changed
    fi

    echo " * Deploying new stack"
    docker stack deploy --prune --compose-file docker-compose.yml "${ADDITIONAL_COMPOSE[@]+"${ADDITIONAL_COMPOSE[@]}"}" --with-registry-auth "$@" fms \
        && docker swarm update --task-history-limit 1
fi
