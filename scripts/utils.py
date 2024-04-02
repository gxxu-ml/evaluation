# SDK usage ref: https://pypi.org/project/ibmcloudant/
# codes assume the env variables CLOUDANT_URL and CLOUDANT_APIKEY are set properly
from ibm_cloud_sdk_core import ApiException
from ibmcloudant.cloudant_v1 import CloudantV1, Document
from tenacity import (
    retry,
    stop_after_attempt,
    wait_random_exponential,
)


def get_client():
    return CloudantV1.new_instance()

def create_db(client, db_name):
    try:
        put_database_result = client.put_database(
            db=db_name
        ).get_result()
        if put_database_result["ok"]:
            print(f'"{db_name}" database created.')
    except ApiException as e:
        if e.status_code == 412:
            print(f'Cannot create "{db_name}" database, it already exists.')

def get_document(client, db_name, doc_id):
    return client.get_document(
        db=db_name,
        doc_id=doc_id
    ).get_result()

def get_documents(client, db_name, as_dict=False):
    response = client.post_all_docs(
        db=db_name, include_docs=True
    ).get_result()
    if as_dict:
        return {row["doc"]["_id"]: row["doc"] for row in response["rows"]}
    else:
        return [row["doc"] for row in response["rows"]]

@retry(wait=wait_random_exponential(min=1, max=60), stop=stop_after_attempt(6))
def create_or_update_document(client, db_name, doc_id, data_dict):
    try:
        doc = get_document(client, db_name, doc_id)
        for k, v in data_dict.items():
            doc[k] = v
        print(f'Updating "{doc_id}" from "{db_name}"...')
    except ApiException as e:
        if e.status_code == 404:
            doc = Document(_id=doc_id, **data_dict)
            print(f'Creating "{doc_id}" in "{db_name}"...')
        else:
            raise e
    return client.post_document(
        db=db_name, document=doc
    ).get_result()
