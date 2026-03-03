const { sql, getPool } = require("../config/db");

// POST /api/tickets
async function createTicket(req, res) {
  const {
    createdByUserId,
    guildId,
    channelId,
    tier = 1,
    title,
    initialMessage = null,
  } = req.body;

  // minimal validation
  if (!createdByUserId || !guildId || !channelId || !title) {
    return res.status(400).json({
      error: "createdByUserId, guildId, channelId, and title are required",
    });
  }

  try {
    const pool = await getPool();
    const request = pool.request();

    request.input("CreatedByUserID", sql.BigInt, createdByUserId);
    request.input("GuildID", sql.BigInt, guildId);
    request.input("ChannelID", sql.BigInt, channelId);
    request.input("Tier", sql.TinyInt, tier);
    request.input("Title", sql.NVarChar(200), title);
    request.input("InitialMessage", sql.NVarChar(sql.MAX), initialMessage);

    request.output("NewTicketID", sql.BigInt);

    await request.execute("support.sp_CreateTicket");

    return res.status(201).json({
      message: "Ticket created",
      ticketId: request.parameters.NewTicketID.value,
    });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
}

// GET /api/tickets/:ticketId
async function getTicketById(req, res) {
  const ticketId = Number(req.params.ticketId);
  if (!ticketId) return res.status(400).json({ error: "Invalid ticketId" });

  try {
    const pool = await getPool();
    const request = pool.request();

    request.input("TicketID", sql.BigInt, ticketId);

    const result = await request.execute("support.sp_GetTicketById");

    const row = result.recordset?.[0];
    if (!row) return res.status(404).json({ error: "Ticket not found" });

    return res.json(row);
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
}

module.exports = { createTicket, getTicketById };
