#!/bin/bash
# Gather Netflix and Amazon AWS IP ranges and put them into single file

rm -f getflix.txt getflix.tmp NF_only.txt netflix_ranges.txt nflix.zip

echo "--> 1. Downloading MaxMind GeoLite2 ASN Database..."

wget -O nflix.zip "https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-ASN-CSV&license_key=${LICENSE_KEY}&suffix=zip"

echo "--> 2. Extracting Netflix ASNs..."

unzip -o -j nflix.zip "*.csv" -d .


ASN_FILE=$(find . -name "*GeoLite2-ASN-Blocks-IPv4.csv" | head -n 1)

if [ -z "$ASN_FILE" ]; then
    echo "Error: ASN CSV file not found in the zip!"
    exit 1
fi

echo "Found ASN File: $ASN_FILE"


grep -i "Netflix" "$ASN_FILE" | cut -d"," -f2 | sort -u > netflix_asn_list.txt


echo "2906" >> netflix_asn_list.txt
echo "394406" >> netflix_asn_list.txt
echo "40027" >> netflix_asn_list.txt
echo "55095" >> netflix_asn_list.txt


sort -u netflix_asn_list.txt -o netflix_asn_list.txt

echo "--> 3. Querying Whois for ASNs..."

while read as_num; do

    as_clean=$(echo $as_num | sed 's/[^0-9]//g')
    if [ ! -z "$as_clean" ]; then
        echo "Querying AS$as_clean..."
        whois -h whois.radb.net -- "-i origin AS$as_clean" | grep -Eo "([0-9.]+){4}/[0-9]+" >> getflix.tmp || true
    fi
done < netflix_asn_list.txt

echo "--> 4. Downloading Community Rules..."

download_rule() {
    url="$1"
    echo "Downloading $url"
    if curl -sSL -O "$url"; then
        filename=$(basename "$url")
        if [ -f "$filename" ]; then
            awk '{match($0, /[0-9]+\.[0-9]+\.[0-9]+\.*[0-9]+\/[0-9]+/); if(RSTART) print substr($0, RSTART, RLENGTH)}' "$filename" >> getflix.tmp
            rm -f "$filename"
        fi
    else
        echo "Warning: Failed to download $url"
    fi
}

download_rule "https://raw.githubusercontent.com/LM-Firefly/Rules/master/Global-Services/Netflix.list"
download_rule "https://raw.githubusercontent.com/GeQ1an/Rules/master/QuantumultX/Filter/Optional/Netflix.list"
download_rule "https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/Ruleset/Netflix.list"
download_rule "https://raw.githubusercontent.com/dler-io/Rules/main/Surge/Surge%203/Provider/Media/Netflix.list"
download_rule "https://raw.githubusercontent.com/Masstone/Rules/master/Lists/Netflix.list"

echo "--> 5. Generating NF_only.txt (Aggregating)..."
# Netflix only IP address ranges
if [ -s getflix.tmp ]; then
    cat getflix.tmp | aggregate -q > NF_only.txt
else
    echo "Warning: getflix.tmp is empty!"
    touch NF_only.txt
fi

echo "--> 6. Processing AWS IP Ranges..."
# Get the Amazon AWS ip range list
curl -sSL -O https://ip-ranges.amazonaws.com/ip-ranges.json
if [ -f ip-ranges.json ]; then

    jq -r '[.prefixes | .[].ip_prefix] - [.prefixes[] | select(.service=="GLOBALACCELERATOR").ip_prefix] - [.prefixes[] | select(.service=="AMAZON").ip_prefix] - [.prefixes[] | select(.region=="cn-north-1").ip_prefix] - [.prefixes[] | select(.region=="cn-northwest-1").ip_prefix] | .[]' < ip-ranges.json >> getflix.tmp || true
    jq -r '[.prefixes | .[].ip_prefix] - [.prefixes[] | select(.service=="EC2").ip_prefix] - [.prefixes[] | select(.service=="AMAZON").ip_prefix] - [.prefixes[] | select(.region=="cn-north-1").ip_prefix] - [.prefixes[] | select(.region=="cn-northwest-1").ip_prefix] | .[]' < ip-ranges.json >> getflix.tmp || true
    jq -r '[.prefixes | .[].ip_prefix] - [.prefixes[] | select(.service=="CLOUDFRONT").ip_prefix] - [.prefixes[] | select(.service=="AMAZON").ip_prefix] - [.prefixes[] | select(.region=="cn-north-1").ip_prefix] - [.prefixes[] | select(.region=="cn-northwest-1").ip_prefix] | .[]' < ip-ranges.json >> getflix.tmp || true
fi

echo "--> 7. Finalizing getflix.txt..."
# unify both the IP address ranges
if [ -s getflix.tmp ]; then
    cat getflix.tmp | aggregate -q > getflix.txt
else
    touch getflix.txt
fi


echo "--> Cleaning up..."
rm -f nflix.zip getflix.tmp netflix_ranges.txt ip-ranges.json netflix_asn_list.txt *.csv

echo "Done."
