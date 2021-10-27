# geoTiffAntimeridianCrossing
Small Script to check input geoTiff raster crosses dateline (antimeridian) and split the raster by dateline

Can be used to cut the raster by dateline into two separate pieces in order to avoid issues with some libraries and applications including gdal, geoserver, geowebcache etc while raster reprojection or tiling 

Inspired by script of plumo user (https://gis.stackexchange.com/users/87998/plumo)
from the post at https://gis.stackexchange.com/questions/34117/how-to-stop-gdalwarp-creating-world-spanning-outputs-near-the-dateline

## usage 
```./checkAntimeridianCrossingAndSplit.sh infile [outfile1 outfile2]```

If no outfiles is given, the script returns "true" or "false" and exits with 0 or 1 error respectively

## notice
This script was tested at geoTiff files with different SRS and tile sizes. Result files are saved in Mercator projection EPSG:3857, change the FINAL_SRS variable to the SRS you want.
Script do several reprojections to EPSG:4326 and back, therefore the total execution time can be quite large as well as the disk space requirements due to the temporary files being created.

To speed up the the execution time remove "-co COMPRESS=DEFLATE" option but it may lead to increase disk space usage by two or more times.

Source file's overview(s) will be swiped out, recreate it again with gdaladdo if needed.
For large tiff files (>3Gb) is'r recomended to add options "-co BIGTIFF=YES" to gdal_translate

Needs gdal 2.0+ and Python
