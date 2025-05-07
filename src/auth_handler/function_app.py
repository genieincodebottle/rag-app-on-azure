import logging
import azure.functions as func
import os
import json
import requests
from urllib.parse import urlencode

app = func.FunctionApp()

# ENV
CLIENT_ID = os.environ.get("CLIENT_ID")
CLIENT_SECRET = os.environ.get("CLIENT_SECRET")
TENANT_ID = os.environ.get("TENANT_ID")  # For Azure B2C or AD
REDIRECT_URI = os.environ.get("REDIRECT_URI")
AUTHORITY_URL = os.environ.get("AUTHORITY_URL")  # e.g., https://login.microsoftonline.com/<tenant_id>
TOKEN_ENDPOINT = f"{AUTHORITY_URL}/oauth2/v2.0/token"

@app.function_name(name="auth_handler")
@app.route(route="auth", methods=["POST"])
def auth_handler(req: func.HttpRequest) -> func.HttpResponse:
    logging.info("Auth handler triggered.")
    try:
        body = req.get_json()
        grant_type = body.get("grant_type", "authorization_code")

        if grant_type == "authorization_code":
            code = body["code"]
            data = {
                "client_id": CLIENT_ID,
                "client_secret": CLIENT_SECRET,
                "code": code,
                "redirect_uri": REDIRECT_URI,
                "grant_type": "authorization_code",
                "scope": "openid profile email"
            }
        elif grant_type == "refresh_token":
            refresh_token = body["refresh_token"]
            data = {
                "client_id": CLIENT_ID,
                "client_secret": CLIENT_SECRET,
                "refresh_token": refresh_token,
                "grant_type": "refresh_token",
                "scope": "openid profile email"
            }
        else:
            return func.HttpResponse(
                json.dumps({"error": "Unsupported grant_type"}),
                status_code=400,
                mimetype="application/json"
            )

        response = requests.post(TOKEN_ENDPOINT, data=data)
        if response.status_code != 200:
            logging.error(f"Token error: {response.text}")
            return func.HttpResponse(response.text, status_code=401)

        return func.HttpResponse(
            response.text,
            status_code=200,
            mimetype="application/json"
        )

    except Exception as e:
        logging.exception("Auth flow failed")
        return func.HttpResponse(f"Error: {str(e)}", status_code=500)
