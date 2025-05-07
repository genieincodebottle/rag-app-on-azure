# src/auth_handler/auth_handler.py

"""
Azure Function to handle authentication operations with Azure AD B2C.
"""
import os
import json
import logging
import azure.functions as func
import requests
import uuid
from datetime import datetime, timedelta
from urllib.parse import urlencode

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger()

# Get environment variables
AAD_B2C_TENANT_ID = os.environ.get('AAD_B2C_TENANT_ID')
AAD_B2C_APPLICATION_ID = os.environ.get('AAD_B2C_APPLICATION_ID')
AAD_B2C_CLIENT_SECRET = os.environ.get('AAD_B2C_CLIENT_SECRET', '')  # Optional, for confidential clients
AAD_B2C_POLICY_NAME = os.environ.get('AAD_B2C_POLICY_NAME', 'B2C_1_SignUpSignIn')
STAGE = os.environ.get('STAGE')

# B2C endpoints
def get_authority_url():
    return f"https://{AAD_B2C_TENANT_ID}.b2clogin.com/{AAD_B2C_TENANT_ID}.onmicrosoft.com/{AAD_B2C_POLICY_NAME}"

def get_token_endpoint():
    return f"{get_authority_url()}/oauth2/v2.0/token"

def get_user_info_endpoint():
    return f"{get_authority_url()}/openid/v2.0/userinfo"

def get_authorize_endpoint():
    return f"{get_authority_url()}/oauth2/v2.0/authorize"

def get_password_reset_endpoint():
    return f"https://{AAD_B2C_TENANT_ID}.b2clogin.com/{AAD_B2C_TENANT_ID}.onmicrosoft.com/B2C_1_PasswordReset/oauth2/v2.0/authorize"

def main(req: func.HttpRequest) -> func.HttpResponse:
    """
    Azure Function to handle authentication operations.
    
    Supported operations:
    - register: Redirect to Azure AD B2C sign-up experience
    - login: Authenticate a user and return tokens
    - verify: Not needed with Azure AD B2C (handled by policy)
    - forgot_password: Redirect to Azure AD B2C password reset
    - refresh_token: Get new tokens using a refresh token
    
    Returns:
        func.HttpResponse: Response with status code and body
    """
    logger.info('Auth handler function processed a request.')
    
    try:
        # Parse request body
        req_body = req.get_json()
        
        # Check if this is a health check request
        if req_body.get('action') == 'healthcheck':
            return func.HttpResponse(
                json.dumps({
                    'message': 'Authentication service is healthy',
                    'stage': STAGE
                }),
                mimetype="application/json",
                status_code=200
            )
        
        # Get operation type
        operation = req_body.get('operation')
        
        if not operation:
            return func.HttpResponse(
                json.dumps({
                    'message': 'Operation is required'
                }),
                mimetype="application/json",
                status_code=400
            )
        
        # Handle different operations
        if operation == 'register':
            return register_user(req_body)
        elif operation == 'login':
            return login_user(req_body)
        elif operation == 'verify':
            return verify_user(req_body)
        elif operation == 'forgot_password':
            return forgot_password(req_body)
        elif operation == 'confirm_forgot_password':
            return confirm_forgot_password(req_body)
        elif operation == 'refresh_token':
            return refresh_token(req_body)
        else:
            return func.HttpResponse(
                json.dumps({
                    'message': f'Unknown operation: {operation}'
                }),
                mimetype="application/json",
                status_code=400
            )
            
    except Exception as e:
        logger.error(f"Error processing authentication: {str(e)}")
        return func.HttpResponse(
            json.dumps({
                'message': f"Error processing authentication: {str(e)}"
            }),
            mimetype="application/json",
            status_code=500
        )

def register_user(params):
    """
    Generate a link to Azure AD B2C sign-up experience.
    
    Args:
        params (dict): Parameters including redirect_uri and others
        
    Returns:
        func.HttpResponse: Response with sign-up URL
    """
    redirect_uri = params.get('redirect_uri', '')
    
    if not redirect_uri:
        return func.HttpResponse(
            json.dumps({
                'message': 'Redirect URI is required'
            }),
            mimetype="application/json",
            status_code=400
        )
    
    # Generate a random state for CSRF protection
    state = str(uuid.uuid4())
    
    # Build the sign-up URL
    auth_url = get_authorize_endpoint()
    query_params = {
        'client_id': AAD_B2C_APPLICATION_ID,
        'response_type': 'code',
        'redirect_uri': redirect_uri,
        'response_mode': 'query',
        'scope': 'openid profile offline_access',
        'state': state
    }
    
    sign_up_url = f"{auth_url}?{urlencode(query_params)}"
    
    return func.HttpResponse(
        json.dumps({
            'message': 'Redirect to sign-up experience',
            'sign_up_url': sign_up_url,
            'state': state
        }),
        mimetype="application/json",
        status_code=200
    )

def login_user(params):
    """
    Handle login authentication flow.
    
    Two different modes:
    1. Direct login with username/password (if policy allows)
    2. Token exchange with authorization code from redirect
    
    Args:
        params (dict): Parameters including username/password or code
        
    Returns:
        func.HttpResponse: Response with authentication result
    """
    # Check if this is a code exchange after redirect
    code = params.get('code')
    redirect_uri = params.get('redirect_uri')
    
    if code and redirect_uri:
        # Exchange authorization code for tokens
        token_endpoint = get_token_endpoint()
        
        token_data = {
            'grant_type': 'authorization_code',
            'client_id': AAD_B2C_APPLICATION_ID,
            'code': code,
            'redirect_uri': redirect_uri,
            'scope': 'openid profile offline_access'
        }
        
        # Add client secret if available (for confidential clients)
        if AAD_B2C_CLIENT_SECRET:
            token_data['client_secret'] = AAD_B2C_CLIENT_SECRET
        
        # Exchange code for tokens
        try:
            response = requests.post(token_endpoint, data=token_data)
            response.raise_for_status()
            token_response = response.json()
            
            return func.HttpResponse(
                json.dumps({
                    'message': 'Login successful',
                    'access_token': token_response.get('access_token'),
                    'id_token': token_response.get('id_token'),
                    'refresh_token': token_response.get('refresh_token'),
                    'expires_in': token_response.get('expires_in'),
                    'token_type': token_response.get('token_type', 'Bearer')
                }),
                mimetype="application/json",
                status_code=200
            )
        except requests.RequestException as e:
            logger.error(f"Error exchanging code for tokens: {str(e)}")
            return func.HttpResponse(
                json.dumps({
                    'message': f"Error exchanging code for tokens: {str(e)}"
                }),
                mimetype="application/json",
                status_code=400
            )
    else:
        # Direct login flow (username/password) - usually not supported with B2C
        # Provide a link to the hosted login page instead
        redirect_uri = params.get('redirect_uri', '')
        
        if not redirect_uri:
            return func.HttpResponse(
                json.dumps({
                    'message': 'Redirect URI is required'
                }),
                mimetype="application/json",
                status_code=400
            )
        
        # Generate a random state for CSRF protection
        state = str(uuid.uuid4())
        
        # Build the login URL
        auth_url = get_authorize_endpoint()
        query_params = {
            'client_id': AAD_B2C_APPLICATION_ID,
            'response_type': 'code',
            'redirect_uri': redirect_uri,
            'response_mode': 'query',
            'scope': 'openid profile offline_access',
            'state': state
        }
        
        login_url = f"{auth_url}?{urlencode(query_params)}"
        
        return func.HttpResponse(
            json.dumps({
                'message': 'Redirect to login page',
                'login_url': login_url,
                'state': state
            }),
            mimetype="application/json",
            status_code=200
        )

def verify_user(params):
    """
    In Azure AD B2C, verification is handled by the policy.
    This is a placeholder function.
    
    Args:
        params (dict): Parameters
        
    Returns:
        func.HttpResponse: Response
    """
    return func.HttpResponse(
        json.dumps({
            'message': 'User verification is handled by Azure AD B2C policy'
        }),
        mimetype="application/json",
        status_code=200
    )

def forgot_password(params):
    """
    Generate a link to Azure AD B2C password reset experience.
    
    Args:
        params (dict): Parameters including redirect_uri
        
    Returns:
        func.HttpResponse: Response with password reset URL
    """
    redirect_uri = params.get('redirect_uri', '')
    
    if not redirect_uri:
        return func.HttpResponse(
            json.dumps({
                'message': 'Redirect URI is required'
            }),
            mimetype="application/json",
            status_code=400
        )
    
    # Generate a random state for CSRF protection
    state = str(uuid.uuid4())
    
    # Build the password reset URL
    reset_url = get_password_reset_endpoint()
    query_params = {
        'client_id': AAD_B2C_APPLICATION_ID,
        'response_type': 'code',
        'redirect_uri': redirect_uri,
        'response_mode': 'query',
        'scope': 'openid profile offline_access',
        'state': state
    }
    
    password_reset_url = f"{reset_url}?{urlencode(query_params)}"
    
    return func.HttpResponse(
        json.dumps({
            'message': 'Redirect to password reset experience',
            'password_reset_url': password_reset_url,
            'state': state
        }),
        mimetype="application/json",
        status_code=200
    )

def confirm_forgot_password(params):
    """
    In Azure AD B2C, password reset confirmation is handled by the policy.
    This is a placeholder function.
    
    Args:
        params (dict): Parameters
        
    Returns:
        func.HttpResponse: Response
    """
    return func.HttpResponse(
        json.dumps({
            'message': 'Password reset confirmation is handled by Azure AD B2C policy'
        }),
        mimetype="application/json",
        status_code=200
    )

def refresh_token(params):
    """
    Get new tokens using a refresh token.
    
    Args:
        params (dict): Parameters including refresh_token
        
    Returns:
        func.HttpResponse: Response with new tokens
    """
    refresh_token = params.get('refresh_token')
    
    if not refresh_token:
        return func.HttpResponse(
            json.dumps({
                'message': 'Refresh token is required'
            }),
            mimetype="application/json",
            status_code=400
        )
    
    # Exchange refresh token for new tokens
    token_endpoint = get_token_endpoint()
    
    token_data = {
        'grant_type': 'refresh_token',
        'client_id': AAD_B2C_APPLICATION_ID,
        'refresh_token': refresh_token,
        'scope': 'openid profile offline_access'
    }
    
    # Add client secret if available (for confidential clients)
    if AAD_B2C_CLIENT_SECRET:
        token_data['client_secret'] = AAD_B2C_CLIENT_SECRET
    
    try:
        response = requests.post(token_endpoint, data=token_data)
        response.raise_for_status()
        token_response = response.json()
        
        return func.HttpResponse(
            json.dumps({
                'message': 'Tokens refreshed successfully',
                'access_token': token_response.get('access_token'),
                'id_token': token_response.get('id_token'),
                'refresh_token': token_response.get('refresh_token'),
                'expires_in': token_response.get('expires_in'),
                'token_type': token_response.get('token_type', 'Bearer')
            }),
            mimetype="application/json",
            status_code=200
        )
    except requests.RequestException as e:
        logger.error(f"Error refreshing tokens: {str(e)}")
        return func.HttpResponse(
            json.dumps({
                'message': 'Refresh token is invalid or expired'
            }),
            mimetype="application/json",
            status_code=401
        )