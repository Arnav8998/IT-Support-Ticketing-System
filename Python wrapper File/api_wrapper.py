import requests

API_BASE_URL = "http://localhost:3000"

# Create a new support ticket
def create_ticket(user_id, title, description):
    response = requests.post(
        f"{API_BASE_URL}/tickets/create",
        json={
            "user_id": user_id,
            "title": title,
            "description": description
        }
    )
    return response.json()


# Get ticket details
def get_ticket(ticket_id):
    response = requests.get(f"{API_BASE_URL}/tickets/{ticket_id}")
    return response.json()


# Close a ticket
def close_ticket(ticket_id):
    response = requests.post(
        f"{API_BASE_URL}/tickets/close",
        json={
            "ticket_id": ticket_id
        }
    )
    return response.json()
