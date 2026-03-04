# API – Database Contract

This document describes the API endpoints that interact with the SQL Server database.

Base URL:
http://localhost:3000

---

## 1. Create Ticket

Endpoint:
POST /tickets/create

Description:
Creates a new support ticket in the system.

Example Request Body:

{
  "user_id": 12345,
  "title": "Login issue",
  "description": "Cannot access system"
}

Example Response:

{
  "status": "success",
  "ticket_id": 101
}

---

## 2. Get Ticket

Endpoint:
GET /tickets/:id

Description:
Retrieves ticket information using the ticket ID.

Example Response:

{
  "ticket_id": 101,
  "status": "open",
  "assigned_to": "support_agent"
}

---

## 3. Close Ticket

Endpoint:
POST /tickets/close

Description:
Closes an existing support ticket.

Example Request Body:

{
  "ticket_id": 101
}

Example Response:

{
  "status": "closed"
}
