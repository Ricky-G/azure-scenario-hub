#!/bin/bash

echo "========================================"
echo "Generating Test Data for Azure Function"
echo "========================================"

# Configuration
NUM_FILES=10
FILE_SIZE_MB=100
ZIP_PASSWORD="password"
OUTPUT_DIR="test-data"
ZIP_FILE="test-data-1gb.zip"

# Create output directory
echo "Creating test data directory..."
mkdir -p $OUTPUT_DIR

# Check if required tools are installed
if ! command -v dd &> /dev/null; then
    echo "Error: 'dd' command not found. Please install it first."
    exit 1
fi

if ! command -v zip &> /dev/null; then
    echo "Error: 'zip' command not found. Please install it first."
    echo "Ubuntu/Debian: sudo apt-get install zip"
    echo "macOS: brew install zip"
    exit 1
fi

# Generate files
echo "Generating $NUM_FILES files of ${FILE_SIZE_MB}MB each..."
for i in $(seq 1 $NUM_FILES); do
    FILE_NAME="$OUTPUT_DIR/test-file-$(printf "%02d" $i).txt"
    echo "Creating $FILE_NAME (${FILE_SIZE_MB}MB)..."
    
    # Create file with random text data
    # Using /dev/urandom and base64 to create text-like content
    dd if=/dev/urandom bs=1M count=$FILE_SIZE_MB 2>/dev/null | base64 > "$FILE_NAME"
    
    # Ensure file is exactly the right size
    truncate -s ${FILE_SIZE_MB}M "$FILE_NAME"
    
    echo "✓ Created $FILE_NAME"
done

# Create password-protected ZIP file
echo ""
echo "Creating password-protected ZIP file..."
cd $OUTPUT_DIR
zip -P "$ZIP_PASSWORD" "../$ZIP_FILE" *.txt
cd ..

# Calculate sizes
TOTAL_SIZE=$((NUM_FILES * FILE_SIZE_MB))
ZIP_SIZE=$(du -h "$ZIP_FILE" | cut -f1)

# Clean up temporary files
echo "Cleaning up temporary files..."
rm -rf $OUTPUT_DIR

# Summary
echo ""
echo "========================================"
echo "Test Data Generation Complete!"
echo "========================================"
echo "Generated: $ZIP_FILE"
echo "Password: $ZIP_PASSWORD"
echo "Contents: $NUM_FILES files × ${FILE_SIZE_MB}MB = ${TOTAL_SIZE}MB uncompressed"
echo "ZIP Size: $ZIP_SIZE"
echo ""
echo "To upload to Azure Storage:"
echo "az storage blob upload \\"
echo "  --account-name <storage-account-name> \\"
echo "  --container-name zipped \\"
echo "  --name $ZIP_FILE \\"
echo "  --file $ZIP_FILE"
echo ""
echo "Or use Azure Storage Explorer for a GUI upload experience."