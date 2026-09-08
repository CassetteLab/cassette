#!/bin/zsh
set -euo pipefail

# Local signing helper. `apply` snapshots the exact repository files before editing them, so
# `restore` puts them back byte-for-byte. The Personal Team is detected from Xcode by default;
# the ignored `.personal-signing.env` file and environment variables can override detection.

SCRIPT_DIR=${0:A:h}
REPO_ROOT=${SCRIPT_DIR:h}
SCRIPT_PATH="$SCRIPT_DIR/${0:t}"
PROJECT_FILE="$REPO_ROOT/Cassette.xcodeproj/project.pbxproj"
APP_ENTITLEMENTS="$REPO_ROOT/Cassette/Cassette-macOS.entitlements"
WIDGET_ENTITLEMENTS="$REPO_ROOT/fr.mathieu-dubart.CassetteWidgetsExtension.entitlements"
BACKUP_DIR="$REPO_ROOT/.personal-signing-backup"
SIGNING_ENV_FILE=${SIGNING_ENV_FILE:-$REPO_ROOT/.personal-signing.env}

if [[ -f $SIGNING_ENV_FILE ]]; then
    source "$SIGNING_ENV_FILE"
fi

REPOSITORY_TEAM_ID=${REPOSITORY_TEAM_ID:-LK2358MPL8}
REPOSITORY_BUNDLE_ID=${REPOSITORY_BUNDLE_ID:-fr.mathieu-dubart.Cassette}

detect_personal_team_id() {
    local teams_output
    teams_output=$(/usr/bin/defaults read com.apple.dt.Xcode \
        IDEProvisioningTeamByIdentifier 2>/dev/null) || return 1

    print -r -- "$teams_output" | /usr/bin/awk '
        /^[[:space:]]*\{/ {
            team_id = ""
            is_personal = 0
        }
        /isFreeProvisioningTeam = 1;/ || /teamType = "Personal Team";/ {
            is_personal = 1
        }
        /teamID = / {
            team_id = $0
            sub(/^.*teamID = /, "", team_id)
            sub(/;.*$/, "", team_id)
            gsub(/"/, "", team_id)
        }
        /^[[:space:]]*\}/ && is_personal && team_id != "" {
            print team_id
        }
    ' | /usr/bin/sort -u
}

resolve_signing_configuration() {
    if [[ -z ${PERSONAL_TEAM_ID:-} ]]; then
        local detected_teams
        detected_teams=("${(@f)$(detect_personal_team_id || true)}")
        detected_teams=("${(@)detected_teams:#}")

        if (( ${#detected_teams} == 0 )); then
            print -u2 "No Personal Team was found in Xcode."
            print -u2 "Add your Apple Account in Xcode > Settings > Accounts, or set PERSONAL_TEAM_ID."
            exit 1
        fi
        if (( ${#detected_teams} > 1 )); then
            print -u2 "Multiple Personal Teams were found: ${detected_teams[*]}"
            print -u2 "Set PERSONAL_TEAM_ID in .personal-signing.env or the environment."
            exit 1
        fi

        PERSONAL_TEAM_ID=$detected_teams[1]
    fi

    # A Team ID is globally unique, making this deterministic bundle identifier very unlikely
    # to collide. It can still be overridden when a specific identifier is preferred.
    PERSONAL_BUNDLE_ID=${PERSONAL_BUNDLE_ID:-com.${(L)PERSONAL_TEAM_ID}.Cassette}
}

validate_identifier() {
    local label=$1
    local value=$2
    if [[ ! $value =~ '^[A-Za-z0-9.-]+$' ]]; then
        print -u2 "Invalid $label: $value"
        exit 2
    fi
}

replace_literal() {
    local file=$1
    local from=$2
    local to=$3
    FROM_TEXT=$from TO_TEXT=$to /usr/bin/perl -0pi -e \
        's/\Q$ENV{FROM_TEXT}\E/$ENV{TO_TEXT}/g' "$file"
}

backup_files() {
    if [[ -e $BACKUP_DIR ]]; then
        print -u2 "Signing backup already exists: $BACKUP_DIR"
        print -u2 "Run '$SCRIPT_PATH restore' before applying again."
        exit 1
    fi
    mkdir -p "$BACKUP_DIR"
    cp "$PROJECT_FILE" "$BACKUP_DIR/project.pbxproj"
    cp "$APP_ENTITLEMENTS" "$BACKUP_DIR/Cassette-macOS.entitlements"
    cp "$WIDGET_ENTITLEMENTS" "$BACKUP_DIR/widgets.entitlements"
}

apply_signing() {
    resolve_signing_configuration
    validate_identifier "team ID" "$PERSONAL_TEAM_ID"
    validate_identifier "bundle ID" "$PERSONAL_BUNDLE_ID"
    backup_files

    replace_literal "$PROJECT_FILE" \
        "DEVELOPMENT_TEAM = $REPOSITORY_TEAM_ID;" \
        "DEVELOPMENT_TEAM = $PERSONAL_TEAM_ID;"
    replace_literal "$PROJECT_FILE" \
        "PRODUCT_BUNDLE_IDENTIFIER = \"$REPOSITORY_BUNDLE_ID\";" \
        "PRODUCT_BUNDLE_IDENTIFIER = $PERSONAL_BUNDLE_ID;"
    replace_literal "$PROJECT_FILE" \
        "PRODUCT_BUNDLE_IDENTIFIER = \"$REPOSITORY_BUNDLE_ID.widgets\";" \
        "PRODUCT_BUNDLE_IDENTIFIER = $PERSONAL_BUNDLE_ID.widgets;"
    replace_literal "$PROJECT_FILE" "REGISTER_APP_GROUPS = YES;" "REGISTER_APP_GROUPS = NO;"

    /usr/libexec/PlistBuddy -c \
        'Delete :com.apple.security.application-groups' "$APP_ENTITLEMENTS" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c \
        'Delete :com.apple.security.application-groups' "$WIDGET_ENTITLEMENTS" 2>/dev/null || true

    print "Applied Personal Team signing:"
    print "  team:    $PERSONAL_TEAM_ID"
    print "  app:     $PERSONAL_BUNDLE_ID"
    print "  widget:  $PERSONAL_BUNDLE_ID.widgets"
    print "Run '$SCRIPT_PATH restore' before creating the pull request."
}

restore_signing() {
    if [[ ! -d $BACKUP_DIR ]]; then
        print -u2 "No signing backup exists at $BACKUP_DIR"
        exit 1
    fi
    cp "$BACKUP_DIR/project.pbxproj" "$PROJECT_FILE"
    cp "$BACKUP_DIR/Cassette-macOS.entitlements" "$APP_ENTITLEMENTS"
    cp "$BACKUP_DIR/widgets.entitlements" "$WIDGET_ENTITLEMENTS"
    rm "$BACKUP_DIR/project.pbxproj"
    rm "$BACKUP_DIR/Cassette-macOS.entitlements"
    rm "$BACKUP_DIR/widgets.entitlements"
    rmdir "$BACKUP_DIR"
    print "Restored repository signing configuration."
}

usage() {
    print "Usage:"
    print "  $SCRIPT_PATH detect"
    print "  $SCRIPT_PATH apply"
    print "  $SCRIPT_PATH restore"
    print "  $SCRIPT_PATH with-build -- xcodebuild <arguments...>"
    print ""
    print "The Personal Team is detected from Xcode and a bundle ID is derived from it."
    print "PERSONAL_TEAM_ID and PERSONAL_BUNDLE_ID can override those values in"
    print ".personal-signing.env or the environment. Repository values are optional."
}

case ${1:-} in
    detect)
        resolve_signing_configuration
        print "Detected Personal Team signing:"
        print "  team:    $PERSONAL_TEAM_ID"
        print "  app:     $PERSONAL_BUNDLE_ID"
        print "  widget:  $PERSONAL_BUNDLE_ID.widgets"
        ;;
    apply)
        apply_signing
        ;;
    restore)
        restore_signing
        ;;
    with-build)
        shift
        [[ ${1:-} == -- ]] && shift
        if (( $# == 0 )); then
            usage
            exit 2
        fi
        apply_signing
        trap restore_signing EXIT INT TERM
        "$@"
        ;;
    *)
        usage
        exit 2
        ;;
esac
