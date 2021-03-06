step_log() {
  message=$1
  printf "\n\033[90;1m==> \033[0m\033[37;1m%s\033[0m\n" "$message"
}

add_log() {
  mark=$1
  shift
  subjects=("$@")
  for subject in "${subjects[@]}"; do
    if [ "$mark" = "$tick" ]; then
      printf "\033[32;1m%s \033[0m\033[34;1m%s \033[0m\033[90;1m%s\033[0m\n" "$mark" "$subject" "Added $subject"
    else
      printf "\033[31;1m%s \033[0m\033[34;1m%s \033[0m\033[90;1m%s\033[0m\n" "$mark" "$subject" "Failed to setup $subject"
    fi
  done
}

get_api_version_from_repo() {
  php_header="https://raw.githubusercontent.com/php/php-src/PHP-$version/main/php.h"
  status_code=$(curl -sSL -o /tmp/php.h -w "%{http_code}" "$php_header")
  if [ "$status_code" != "200" ]; then
    curl -sSL --retry 5 "${php_header/PHP-$version/master}" | grep "PHP_API_VERSION" | cut -d' ' -f 3
  else
    grep "PHP_API_VERSION" /tmp/php.h | cut -d' ' -f 3
  fi
}

get_api_version() {
  case $version in
  5.3) echo "20090626" ;;
  5.4) echo "20100525" ;;
  5.5) echo "20121212" ;;
  5.6) echo "20131226" ;;
  7.0) echo "20151012" ;;
  7.1) echo "20160303" ;;
  7.2) echo "20170718" ;;
  7.3) echo "20180731" ;;
  7.4) echo "20190902" ;;
  8.0) echo "20200930" ;;
  *) get_api_version_from_repo ;;
  esac
}

fix_ownership() {
  dir=$1
  sudo chown -R "$USER":"$(id -g -n)" "$(dirname "$dir")"
}

add_config() {
  dependent_extension=$1
  dependency_extension=$2
  echo "$dependency_extension" | sudo tee "${ext_config_directory:?}/$dependent_extension/$dependency_extension" >/dev/null 2>&1
}

extension_dir_darwin() {
  api_version=$1
  if [[ "${version:?}" =~ ${old_versions:?} ]]; then
    echo "/opt/local/lib/php${version/./}/extensions/no-debug-non-zts-$api_version"
  else
    if [[ "$(sysctl -n hw.optional.arm64 2>/dev/null)" == "1" ]]; then
      echo "/opt/homebrew/lib/php/pecl/$api_version"
    else
      echo "/usr/local/lib/php/pecl/$api_version"
    fi
  fi
}

extension_dir_linux() {
  api_version=$1
  if [[ "${version:?}" =~ ${old_versions:?}|${nightly_versions:?} ]]; then
    echo "/usr/local/php/$version/lib/php/extensions/no-debug-non-zts-$api_version"
  else
    echo "/usr/lib/php/$api_version"
  fi
}

data() {
  old_versions="5.[3-5]"
  nightly_versions="8.[1-9]"
  date='20210703'
  if [ "$os" = "Linux" ]; then
    . /etc/lsb-release
    os=$os-$DISTRIB_CODENAME
    api_version=$(get_api_version)
    dir=$(extension_dir_linux "$api_version")
    sudo mkdir -p "$dir/deps" && fix_ownership "$dir"
  elif [ "$os" = "Darwin" ]; then
    api_version=$(get_api_version)
    dir=$(extension_dir_darwin "$api_version")
    sudo mkdir -p "$dir/deps" && fix_ownership "$dir"
    date='20210707'
  else
    os="Windows"
    dir='C:\\tools\\php\\ext'
    [[ "$extensions" == *"imagick"* ]] && date='20210512'
  fi
  key="$os"-ext-"$version"-$(echo -n "$extensions-$key" | openssl dgst -sha256 | cut -d ' ' -f 2)
  key="$key-$date"
  echo "$dir" > "${RUNNER_TEMP:?}"/dir
  echo "$key" > "${RUNNER_TEMP:?}"/key
  echo "::set-output name=dir::$dir"
  echo "::set-output name=key::$key"
}

dependencies() {
  if [ "$os" = "Linux" ] || [ "$os" = "Darwin" ]; then
    export tick="✓"
    export cross="✗"
    export ext_config_directory="/tmp/extcache"
    export deps_cache_directory="${RUNNER_TOOL_CACHE}"/deps
    script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)
    # shellcheck disable=SC1090
    . "$script_dir/$(echo "$os" | tr '[:upper:]' '[:lower:]').sh"
    setup_dependencies "$extensions" "$(cat "${RUNNER_TEMP:?}"/dir)"
  fi
}

run=$1
extensions=$2
version=$3
key=$4
os=$(uname -s)

$run
