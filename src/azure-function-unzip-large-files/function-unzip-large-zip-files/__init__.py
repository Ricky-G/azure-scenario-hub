import logging
import os
import tempfile
import pyzipper
import azure.functions as func
from azure.storage.blob import BlobServiceClient, BlobBlock
from dotenv import load_dotenv
import uuid

load_dotenv()

def main(myblob: func.InputStream) -> None:
    logging.info(f'Python blob trigger function processing blob \n'
                 f'Name: {myblob.name}\n'
                 f'Blob Size: {myblob.length} bytes')
    
    try:
        connection_string = os.getenv('STORAGE_CONNECTION_STRING')
        if not connection_string:
            connection_string = os.environ['AzureWebJobsStorage']
        
        source_container = os.getenv('SOURCE_CONTAINER_NAME', 'zipped')
        dest_container = os.getenv('DESTINATION_CONTAINER_NAME', 'unzipped')
        zip_password = os.getenv('ZIP_PASSWORD')
        if not zip_password:
            raise ValueError("ZIP_PASSWORD environment variable is not set. Please configure it in your application settings.")
        
        blob_service_client = BlobServiceClient.from_connection_string(connection_string)
        dest_container_client = blob_service_client.get_container_client(dest_container)
        
        try:
            dest_container_client.create_container()
            logging.info(f"Created container: {dest_container}")
        except Exception:
            logging.info(f"Container {dest_container} already exists")
        
        blob_name = myblob.name.split('/')[-1]
        base_name = os.path.splitext(blob_name)[0]
        
        chunk_size = 4 * 1024 * 1024  # 4MB chunks
        
        with tempfile.NamedTemporaryFile(delete=False) as temp_file:
            temp_path = temp_file.name
            for chunk in iter(lambda: myblob.read(chunk_size), b''):
                temp_file.write(chunk)
        
        try:
            with pyzipper.AESZipFile(temp_path) as zf:
                zf.setpassword(zip_password.encode('utf-8'))
                
                for file_info in zf.infolist():
                    if file_info.is_dir():
                        continue
                    
                    logging.info(f"Extracting: {file_info.filename} ({file_info.file_size} bytes)")
                    
                    dest_blob_name = f"{base_name}/{file_info.filename}"
                    dest_blob_client = dest_container_client.get_blob_client(dest_blob_name)
                    
                    block_list = []
                    block_index = 0
                    
                    with zf.open(file_info) as source_file:
                        while True:
                            chunk = source_file.read(chunk_size)
                            if not chunk:
                                break
                            
                            block_id = str(uuid.uuid4())
                            dest_blob_client.stage_block(block_id, chunk, len(chunk))
                            block_list.append(BlobBlock(block_id=block_id))
                            block_index += 1
                            
                            if block_index % 10 == 0:
                                logging.info(f"Staged {block_index} blocks for {file_info.filename}")
                    
                    dest_blob_client.commit_block_list(block_list)
                    logging.info(f"Successfully extracted {file_info.filename} to {dest_blob_name}")
            
            logging.info(f"Successfully processed ZIP file: {blob_name}")
            
        finally:
            if os.path.exists(temp_path):
                os.unlink(temp_path)
        
    except Exception as e:
        logging.error(f"Error processing blob {myblob.name}: {str(e)}")
        raise