# Combine results of the same architecture into a library for that architecture
source_combined=""
for arch in ${archs[*]}; do
    source_libraries=""

    mkdir $arch
    cd $arch
    for library in ${libraries[*]}; do
        # Extract the libraries, overwriting duplicated files with the same name in each lib
        ar x ../${library}_${arch}.a
        rm __.SYMDEF
        # Hack specific to one usecase: don't deduplicate Utils.o, both versions must be kept
        mv Utils.o ${library}_Utils.o
        source_libraries="${source_libraries} ${library}_${arch}.a"
    done
    cd ..

    $libtool -static ${arch}/*.o -o "${1}_${arch}.a"
    source_combined="${source_combined} ${1}_${arch}.a"

    # Delete intermediate files
    rm ${source_libraries}
    rm -rf ${arch}
done

# Merge the combined library for each architecture into a single fat binary
lipo -create $source_combined -o $1.a

# Delete intermediate files
rm ${source_combined}

# Show info on the output library as confirmation
echo "Combination complete."
lipo -info $1.aÎ
