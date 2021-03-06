link_apt_fast() {
  if ! command -v apt-fast >/dev/null; then
    sudo ln -sf /usr/bin/apt-get /usr/bin/apt-fast
  fi
}

fetch_package() {
  if ! [ -e /tmp/Packages ]; then
    . /etc/lsb-release
    deb_build_arch=$(dpkg-architecture -q DEB_BUILD_ARCH)
    curl -o /tmp/Packages.gz -sL "http://ppa.launchpad.net/ondrej/php/ubuntu/dists/$DISTRIB_CODENAME/main/binary-$deb_build_arch/Packages.gz"
    gzip -df /tmp/Packages.gz
  fi
}

get_dependencies() {
  package=$1
  prefix=$2
  sed -e '/Package:\s'"$package$"'/,/^\s*$/!d' /tmp/Packages | grep -Eo "^Depends.*" | tr ',' '\n' | awk -v ORS='' '/^\s'"$prefix"'/{print$0}' | sed -e 's/([^()]*)//g' | sort | uniq | xargs echo -n
}

get_package_link() {
  package=$1
  trunk="http://ppa.launchpad.net/ondrej/php/ubuntu"
  file=$(sed -e '/Package:\s'"$package$"'/,/^\s*$/!d' /tmp/Packages | grep -Eo "^Filename.*" | cut -d' ' -f 2 | tr -d '\r')
  echo "$trunk/$file"
}

setup_extensions_helper() {
  dependency_extension=$1
  extension_dir=$2
  cached_extension="${deps_cache_directory:?}/$dependency_extension.so"
  if ! [ -e "$extension_dir/$dependency_extension.so" ]; then
    if ! [ -e "$cached_extension" ]; then
      extension_package_link="$(get_package_link "php${version:?}-$dependency_extension")"
      sudo curl -H "User-Agent: Debian APT-HTTP/GHA(ce)" -o "/tmp/$dependency_extension".deb -sL "$extension_package_link"
      sudo dpkg-deb -x "/tmp/$dependency_extension".deb /
      sudo cp "$extension_dir/$dependency_extension.so" "$cached_extension"
      fix_ownership "$extension_dir"
    else
      sudo cp "$cached_extension" "$extension_dir/"
    fi
  fi
}

setup_extensions() {
  extension_dir=$1
  IFS=' ' read -r -a dependency_extension_array <<<"$(echo "$2" | xargs -n1 | sort | uniq | xargs)"
  to_wait=()
  for dependency_extension in "${dependency_extension_array[@]}"; do
    setup_extensions_helper "$dependency_extension" "$extension_dir" &
    to_wait+=($!)
  done
  wait "${to_wait[@]}"
  add_log "${tick:?}" "${dependency_extension_array[@]}"
}

filter_libraries() {
  libraries="$(echo "$1" | xargs -n1 | sort | uniq | xargs)"
  for library in $libraries; do
    if grep -i -q -w "$library" "${script_dir:?}"/../lists/"$DISTRIB_CODENAME"-libs; then
      libraries=${libraries//$library/}
    fi
  done
  echo "$libraries"
}

setup_libraries() {
  libraries=$1
  if [[ -n "${libraries// /}" ]]; then
    libraries=$(filter_libraries "$libraries")
    if [[ -n "${libraries// /}" ]]; then
      step_log "Setup libraries"
      IFS=' ' read -r -a libraries_array <<<"$libraries"
      link_apt_fast
      echo "::group::Logs to set up required libraries"
      sudo DEBIAN_FRONTEND=noninteractive apt-fast install --no-install-recommends --no-upgrade -y "${libraries_array[@]}"
      ec="$?"
      echo "::endgroup::"
      if [ "$ec" -eq "0" ]; then mark="${tick:?}"; else mark="${cross:?}"; fi
      add_log "$mark" "${libraries_array[@]}"
    fi
  fi
}

setup_dependencies() {
  extensions=$1
  extension_dir=$2
  [[ -z "${extensions// }" ]] && return
  IFS=' ' read -r -a extensions_array <<<"$(echo "$extensions" | sed -e "s/pdo[_-]//g" -Ee "s/^|,\s*/ php$version-/g")"
  . /etc/lsb-release
  sudo rm -rf "${ext_config_directory:?}" || true
  libraries=""
  extension_packages=""
  for extension_package in "${extensions_array[@]}"; do
    fetch_package
    libraries="$libraries $(get_dependencies "$extension_package" "lib")"
    extension_packages="$extension_packages $(get_dependencies "$extension_package" "php$version-")"
    extension_packages="${extension_packages//php$version-common/}"
  done
  if [[ -n "${libraries// /}" ]]; then
    setup_libraries "$libraries"
  fi
  if [[ -n "${extension_packages// /}" ]]; then
    setup_extensions "$extension_dir" "${extension_packages//php$version-/}"
  fi
}
