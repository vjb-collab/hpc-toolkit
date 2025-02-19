#!/bin/bash
set -e

PREFIX="spack:"

echo "$PREFIX Beginning setup..."
if [[ $EUID -ne 0 ]]; then
  echo "$PREFIX This script must be run as root"
  exit 1
fi

# Activate ghpc-venv virtual environment if it exists
if [ -d /usr/local/ghpc-venv ]; then
  source /usr/local/ghpc-venv/bin/activate
fi

# Only install and configure spack if ${INSTALL_DIR} doesn't exist
if [ ! -d ${INSTALL_DIR} ]; then

  # Install spack
  echo "$PREFIX Installing spack from ${SPACK_URL}..."
  {
  mkdir -p ${INSTALL_DIR};
  chmod a+rwx ${INSTALL_DIR};
  chmod a+s ${INSTALL_DIR};
  cd ${INSTALL_DIR};
  git clone --no-checkout ${SPACK_URL} .
  } &>> ${LOG_FILE}
  echo "$PREFIX Checking out ${SPACK_REF}..."
  git checkout ${SPACK_REF} >> ${LOG_FILE} 2>&1

  {
  source ${INSTALL_DIR}/share/spack/setup-env.sh;
  spack compiler find --scope site
  } &>> ${LOG_FILE} 2>&1

  echo "$PREFIX Configuring spack..."
  %{for c in CONFIGS ~}
    %{if c.type == "single-config" ~}
      spack config --scope=${c.scope} add "${c.content}" >> ${LOG_FILE} 2>&1
    %{endif ~}

    %{if c.type == "file" ~}
      {
      cat << 'EOF' > ${INSTALL_DIR}/spack_conf.yaml
${c.content}
EOF

      spack config --scope=${c.scope} add -f ${INSTALL_DIR}/spack_conf.yaml
      rm -f ${INSTALL_DIR}/spack_conf.yaml
      } &>> ${LOG_FILE} 2>&1
    %{endif ~}
  %{endfor ~}

  echo "$PREFIX Setting up spack mirrors..."
  %{for m in MIRRORS ~}
  spack mirror add --scope site ${m.mirror_name} ${m.mirror_url} >> ${LOG_FILE} 2>&1
  %{endfor ~}

  echo "$PREFIX Installing GPG keys"
  spack gpg init >> ${LOG_FILE} 2>&1
  %{for k in GPG_KEYS ~}
    %{if k.type == "file" ~}
      spack gpg trust ${k.path}
    %{endif ~}

    %{if k.type == "new" ~}
      spack gpg create "${k.name}" ${k.email}
    %{endif ~}
  %{endfor ~}

  spack buildcache keys --install --trust >> ${LOG_FILE} 2>&1
else
  source ${INSTALL_DIR}/share/spack/setup-env.sh >> ${LOG_FILE} 2>&1
fi

echo "$PREFIX Installing licenses..."
%{for lic in LICENSES ~}
  gsutil cp ${lic.source} ${lic.dest} >> ${LOG_FILE} 2>&1
%{endfor ~}

echo "$PREFIX Installing compilers..."
%{for c in COMPILERS ~}
  {
    spack install ${INSTALL_FLAGS} ${c};
    spack load ${c};
    spack clean -s
  } &>> ${LOG_FILE}
%{endfor ~}

spack compiler find --scope site >> ${LOG_FILE} 2>&1

echo "$PREFIX Installing root spack specs..."
%{for p in PACKAGES ~}
  spack install ${INSTALL_FLAGS} ${p} >> ${LOG_FILE} 2>&1
  spack clean -s
%{endfor ~}

echo "$PREFIX Configuring spack environments"
%{if ENVIRONMENTS != null ~}
%{for e in ENVIRONMENTS ~}
if [ ! -d ${INSTALL_DIR}/var/spack/environments/${e.name} ]; then
  %{if e.content != null}
    {
      cat << 'EOF' > ${INSTALL_DIR}/spack_env.yaml
${e.content}
EOF
      spack env create ${e.name} ${INSTALL_DIR}/spack_env.yaml
      rm -f ${INSTALL_DIR}/spack_env.yaml
    } &>> ${LOG_FILE}
  %{else ~}
      spack env create ${e.name} >> ${LOG_FILE} 2>&1
  %{endif ~}

  spack env activate ${e.name} >> ${LOG_FILE} 2>&1

  %{if e.packages != null}
    echo "$PREFIX    Configuring spack environment ${e.name}"
    %{for p in e.packages ~}
      spack add ${p} >> ${LOG_FILE} 2>&1
    %{endfor ~}
  %{endif ~}

  echo "$PREFIX    Concretizing spack environment ${e.name}"
  spack concretize ${CONCRETIZE_FLAGS} >> ${LOG_FILE} 2>&1

  echo "$PREFIX    Installing packages for spack environment ${e.name}"
  # shellcheck disable=SC2129
  spack install ${INSTALL_FLAGS} >> ${LOG_FILE} 2>&1

  spack env deactivate >> ${LOG_FILE} 2>&1
  spack clean -s >> ${LOG_FILE} 2>&1
fi
%{endfor ~}
%{endif ~}

echo "$PREFIX Populating defined buildcaches"
%{for c in CACHES_TO_POPULATE ~}
  %{if c.type == "directory" ~}
    # shellcheck disable=SC2046
    {
      spack buildcache create -d ${c.path} -af $(spack find --format /{hash});
      spack gpg publish -d ${c.path};
      spack buildcache update-index -d ${c.path} --keys;
    } >> ${LOG_FILE}
  %{endif ~}
  %{if c.type == "mirror" ~}
    # shellcheck disable=SC2046
    {
      spack buildcache create --mirror-url ${c.path} -af $(spack find --format /{hash});
      spack gpg publish --mirror-url ${c.path};
      spack buildcache update-index --mirror-url ${c.path} --keys;
    } >> ${LOG_FILE}
  %{endif ~}
%{endfor ~}

if [ ! -f /etc/profile.d/spack.sh ]; then
        echo "source ${INSTALL_DIR}/share/spack/setup-env.sh" > /etc/profile.d/spack.sh
        chmod a+rx /etc/profile.d/spack.sh
fi

echo "$PREFIX Setup complete..."
