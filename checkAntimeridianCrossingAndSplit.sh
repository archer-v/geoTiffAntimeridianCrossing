#!/bin/bash
#
# Small Script to check input raster crosses dateline (antimeridian) 
# and split the raster by dateline
# 
# Can be used to cut the raster by dateline into two separate pieces in order to avoid 
# a lot of raster reprojection or tiling issues with some libraries and applications including gdal, geoserver, geowebcache etc
#
# Inspired by script of plumo user (https://gis.stackexchange.com/users/87998/plumo)
# from the post at https://gis.stackexchange.com/questions/34117/how-to-stop-gdalwarp-creating-world-spanning-outputs-near-the-dateline
#
# USAGE: ./checkAntimeridianCrossingAndSplit.sh infile [outfile1 outfile2]
# 
# if no outfile is given, the script returns "true" or "false" and exits with 0 or 1 error respectively
# 
# This script tested at geoTiff files with different SRS and tile sizes
# Result files are saved in Mercator projection EPSG:3857, change the FINAL_SRS to the SRS you want
#
# Because script do several reprojections to EPSG:4326 and back, the total execution time can be quite large as well as the disk space requirements due to the temporary files being created.
# To speed up the the execution time remove "-co COMPRESS=DEFLATE" option but it may lead to increase disk space usage by two or more times
#
# Source file's overview(s) will be swiped out if it was exist, recreate it again with gdaladdo
#
# For large tiff files (>3Gb) is'r recomended to add options "-co BIGTIFF=YES" to gdal_translate
#
# Needs gdal 2.0+ and Python
# 



WARP_OPTIONS="-overwrite -multi -wo NUM_THREADS=ALL_CPUS -wm 2048 --config GDAL_CACHEMAX 1024 -wo OPTIMIZE_SIZE -co TILED=YES -co BLOCKXSIZE=512 -co BLOCKYSIZE=512 -co COMPRESS=DEFLATE"
TRANSLATE_OPTIONS="-co TILED=YES -co BLOCKXSIZE=512 -co BLOCKYSIZE=512 -co COMPRESS=DEFLATE -co NUM_THREADS=ALL_CPUS"
FINAL_SRS="EPSG:3857"

if [ -z "$1" ]; then
    echo -e "Error: No input rasterfile given.\n> USAGE: $0 infile [outfile_before_dateline outfile_after_dateline]"
    exit
fi

outfileB=$2
outfileA=$3

# Get information, save it to variable as we need it several times
gdalinfo=$(gdalinfo "${1}" -json)

# If -json switch is not available exit!
if [ ! -z $(echo $gdalinfo | grep "^Usage:") ]; then
    echo -e "Error: GDAL command failed, Version 2.0+ is needed"
    exit
fi

function jsonq {
    echo "${1}" | python -c "import json,sys; jdata = sys.stdin.read(); data = json.loads(jdata); print(data${2});"
}

ulx=$(jsonq "$gdalinfo" "['wgs84Extent']['coordinates'][0][0][0]")
uly=$(jsonq "$gdalinfo" "['wgs84Extent']['coordinates'][0][0][1]")
llx=$(jsonq "$gdalinfo" "['wgs84Extent']['coordinates'][0][1][0]")
lly=$(jsonq "$gdalinfo" "['wgs84Extent']['coordinates'][0][1][1]")
lrx=$(jsonq "$gdalinfo" "['wgs84Extent']['coordinates'][0][2][0]")
lry=$(jsonq "$gdalinfo" "['wgs84Extent']['coordinates'][0][2][1]")
urx=$(jsonq "$gdalinfo" "['wgs84Extent']['coordinates'][0][3][0]")
ury=$(jsonq "$gdalinfo" "['wgs84Extent']['coordinates'][0][3][1]")

crossing_dateline=false
test $(echo "${ulx}>${lrx}" | bc) -eq 1 && crossing_dateline=true
test $(echo "${llx}>${urx}" | bc) -eq 1 && crossing_dateline=true

echo "${crossing_dateline}"

if [ "$outfileA" = "" -a "$outfileB" = "" ]; then
    if [ "${crossing_dateline}" == "true" ]; then
        exit 0
    else
        exit 1
    fi
fi

echo "Try to split $1 to $2 and $3 along the dateline"

#calc the A cutting shape
test $(echo "${ulx}>${llx}" | bc) -eq 1 && bulx=$llx || bulx=$ulx
buly=$uly
blrx=180
blry=$lry

#calc the B cutting shape
aulx=180
auly=$ury
test $(echo "${urx}>${lrx}" | bc) -eq 1 && alrx_neg=$urx || alrx_neg=$lrx
alrx=$(echo "180 + ${alrx_neg} + 180" | bc)
alry=$lry


echo "src B region ${bulx} ${buly} ${blrx} ${blry}"
echo "src A region ${aulx} ${auly} ${alrx} ${alry}"

#reproject raster to 4326 SRS
#i don't know the way we can split along dateline in projection other than 4326 (gdalwarp dies on rasters with dateline while cutting and reprojections on another SRS)
gdalwarp ${WARP_OPTIONS} --config CENTER_LONG 180 -t_srs EPSG:4326 $1 4326_${1}

#create the "after" dateline part
gdal_translate -projwin ${bulx} ${buly} ${blrx} ${blry} -projwin_srs EPSG:4326 ${TRANSLATE_OPTIONS} 4326_${1} 4326_b_${1}
#create the "before" dateline part
gdal_translate -projwin ${aulx} ${auly} ${alrx} ${alry} -projwin_srs EPSG:4326 ${TRANSLATE_OPTIONS} 4326_${1} 4326_a_${1}
#clean up
rm -f 4326_${1}
#reproject "before" part to the final destination SRS
gdalwarp ${WARP_OPTIONS} -t_srs ${FINAL_SRS} 4326_b_${1} ${outfileB}
#clean up
rm -f 4326_b_${1}
#fix box coordinates for "after" part (shift into -180 range)
aulx=-180
alrx=$alrx_neg
gdal_translate ${TRANSLATE_OPTIONS} -a_ullr ${aulx} ${auly} ${alrx} ${alry} 4326_a_${1} 4326_at_${1}
#clean up
rm -f 4326_a_${1}
#reproject "after" part to the final destination SRS
gdalwarp ${WARP_OPTIONS} -t_srs ${FINAL_SRS} 4326_at_${1} ${outfileA}

#clean up
rm -f 4326_at_${1}

echo "dst B region ${bulx} ${buly} ${blrx} ${blry}"
echo "dst A region ${aulx} ${auly} ${alrx} ${alry}"

