#! /bin/bash

# Make a new git tag and upload a new release.
######################################################################
# The tag's name (a version string like `v1.2.3') and the commit
# message come from the topmost entry of ../NEWS.  Headlines of those
# entries are supposed to start with `* ' and must contain the version
# string unquoted and surrounded by whitespace.

workdir=`pwd`

function latest_NEWS_section {
    # Extract topmost section from NEWS.
    sed -nr \
        -e '/^\* .*v[0-9]+\.[0-9]+\.[0-9]+.*$/,/(^\* .*v[0-9]+\.[0-9]+\.[0-9]+.*$)|(^; .*$)/{H}' \
        -e '${g; s/(\n\* .*v[0-9]+\.[0-9]+\.[0-9]+.*$)|(\n; .*$)//m2; s/^\n//m1; p}' \
        $workdir/../NEWS
}

function latest_version_number {
    # Extract version string from topmost headline in NEWS.
    latest_NEWS_section | \
        grep -Eom 1 -e 'v[0-9]+\.[0-9]+\.[0-9]+'
}

function naked_version_number {
    # Version string without the leading `v'.
    version=`latest_version_number`
    echo ${version#v}
}

# program_version_number <program_file>
function program_version_number {
    grep -Em 1 -e '\$version *=.*v[0-9]+\.[0-9]+\.?[0-9]*.*;' $1 | \
        grep -Eom 1 -e 'v[0-9]+\.[0-9]+\.?[0-9]*'
}

echo "Tagging `latest_version_number`"

if [[ -n `git-diff` ]]; then
    echo "We have uncommitted changes."
    git-status
    echo "Aborting."
    exit
fi;

if [[ `program_version_number ../monikop` != `latest_version_number` ]]; then
    echo "Version number mismatch between monikop and NEWS. Aborting."
    exit
elif [[ `program_version_number ../pokinom` != `latest_version_number` ]]; then
    echo "Version number mismatch between pokinom and NEWS. Aborting."
    exit
fi

if ! git-tag -a -m "`latest_NEWS_section`" `latest_version_number`; then
    echo "Setting tag `latest_version_number` failed. But maybe things are already in place."
else
    echo "Tagging `latest_version_number` successful."
fi

if [[ `git-describe $(latest_version_number)` != `latest_version_number` ]]; then
    echo "Tag `latest_version_number` missing. Aborting."
    exit
fi

echo "Writing archive ../monikop-`naked_version_number`.tar.gz."
if ! (
        cd ..
        git-archive \
            --format=tar \
            --prefix=monikop-`naked_version_number`/ `latest_version_number` | \
            gzip > monikop-`naked_version_number`.tar.gz
        )
then
    echo "Unsuccessful. Aborting."
    exit
fi

echo "Writing instruct-ohloh-`naked_version_number`.xml."
if ! cat > instruct-ohloh-`naked_version_number`.xml <<EOF
<packages>
  <package name="Monikop">
    <releases>
      <release name="`latest_version_number`">
        <files>
          <file name="monikop-`naked_version_number`.tar.gz"/>
        </files>
      </release>
    </releases>
  </package>
</packages>
EOF
then
    echo "Unsuccessful. Aborting."
    exit
fi

echo "Uploading to upload.ohloh.net."
scp ../monikop-`naked_version_number`.tar.gz trebb@upload.ohloh.net:monikop/files &&
scp instruct-ohloh-`naked_version_number`.xml trebb@upload.ohloh.net:monikop/instructs

exit
