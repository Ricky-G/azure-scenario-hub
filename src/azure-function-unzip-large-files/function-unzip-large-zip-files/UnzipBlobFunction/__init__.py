import logging
import os
import pyzipper
import azure.functions as func
from azure.storage.blob import BlobServiceClient, BlobBlock
from dotenv import load_dotenv
import uuid
from io import BytesIO

load_dotenv()

def main(myblob: func.InputStream) -> None:
    blob_name = myblob.name.split('/')[-1]
    logging.info(f'📦 Processing ZIP file: {blob_name} ({myblob.length:,} bytes)')
    
    try:
        connection_string = os.getenv('STORAGE_CONNECTION_STRING')
        if not connection_string:
            connection_string = os.environ['AzureWebJobsStorage']
        
        source_container = os.getenv('SOURCE_CONTAINER_NAME', 'zipped')
        dest_container = os.getenv('DESTINATION_CONTAINER_NAME', 'unzipped')
        zip_password = os.getenv('ZIP_PASSWORD')
        if not zip_password:
            raise ValueError("ZIP_PASSWORD environment variable is not set.")
        
        # Disable Azure SDK logging to reduce noise
        import logging as azure_logging
        azure_logging.getLogger('azure').setLevel(azure_logging.WARNING)
        azure_logging.getLogger('azure.storage').setLevel(azure_logging.WARNING)
        
        blob_service_client = BlobServiceClient.from_connection_string(connection_string)
        dest_container_client = blob_service_client.get_container_client(dest_container)
        
        try:
            dest_container_client.create_container()
            logging.info(f"📁 Created destination container: {dest_container}")
        except Exception:
            pass  # Container already exists
        
        base_name = os.path.splitext(blob_name)[0]
        
        # Read ZIP file into memory for processing
        logging.info(f"📥 Reading ZIP file into memory...")
        zip_data = myblob.read()
        zip_stream = BytesIO(zip_data)
        
        logging.info(f"📥 ZIP file loaded ({len(zip_data) // (1024*1024)}MB)")
        
        with pyzipper.AESZipFile(zip_stream) as zf:
            zf.setpassword(zip_password.encode('utf-8'))
            
            file_list = [f for f in zf.infolist() if not f.is_dir()]
            total_files = len(file_list)
            
            logging.info(f"🗂️  Found {total_files} files in ZIP archive")
            
            for index, file_info in enumerate(file_list, 1):
                file_size_mb = file_info.file_size / (1024 * 1024)
                logging.info(f"📄 [{index}/{total_files}] Extracting: {file_info.filename} ({file_size_mb:.1f} MB)")
                
                dest_blob_name = f"{base_name}/{file_info.filename}"
                dest_blob_client = dest_container_client.get_blob_client(dest_blob_name)
                
                block_list = []
                total_bytes_processed = 0
                chunk_size = 4 * 1024 * 1024  # 4MB chunks
                
                # Extract file in chunks and upload to blob
                with zf.open(file_info) as source_file:
                    while True:
                        chunk = source_file.read(chunk_size)
                        if not chunk:
                            break
                        
                        block_id = str(uuid.uuid4())
                        dest_blob_client.stage_block(block_id, chunk)
                        block_list.append(BlobBlock(block_id=block_id))
                        total_bytes_processed += len(chunk)
                        
                        # Log progress for large files
                        if total_bytes_processed % (50 * 1024 * 1024) == 0:  # Every 50MB
                            progress_mb = total_bytes_processed // (1024 * 1024)
                            logging.info(f"📄 [{index}/{total_files}] Progress: {progress_mb}MB")
                
                dest_blob_client.commit_block_list(block_list)
                logging.info(f"✅ [{index}/{total_files}] Completed: {file_info.filename} ({file_size_mb:.1f} MB)")
        
        logging.info(f"🎉 Successfully processed ZIP file: {blob_name} - Extracted {total_files} files")
        
    except Exception as e:
        logging.error(f"Error processing blob {myblob.name}: {str(e)}")
        raise
