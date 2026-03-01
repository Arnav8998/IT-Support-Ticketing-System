USE ITSupportTicketingDB;
GO
SELECT s.name AS [Schema], t.name AS [Table]
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id = t.schema_id
ORDER BY s.name, t.name;
/*
=========================================================
 MASTER BUILD SCRIPT (ONE-PASTE) — SQL Server
 IT Support Ticketing & Escalation System (MVP)
=========================================================

What this does (in order):
A) Create DB (if missing) + USE it
B) Create schema [support]
C) Drop existing procedures (if any)
D) Drop existing tables (in FK-safe order)
E) Create tables + constraints
F) Create indexes + trigger
G) Create stored procedures (backend queries)
H) Seed demo data (idempotent)
I) Run a quick end-to-end test (CreateTicket + GetThread + ListOpen)

Safe to re-run multiple times.
*/

SET NOCOUNT ON;
GO

/* =========================
   A) Create DB + USE DB
   ========================= */
IF DB_ID('ITSupportTicketingDB') IS NULL
BEGIN
    PRINT 'Creating database ITSupportTicketingDB...';
    CREATE DATABASE ITSupportTicketingDB;
END
GO

USE ITSupportTicketingDB;
GO

/* =========================
   B) Create schema
   ========================= */
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'support')
BEGIN
    EXEC('CREATE SCHEMA support');
END
GO

/* =========================
   C) Drop procedures (if exist)
   ========================= */
DECLARE @proc SYSNAME;

DECLARE proc_cursor CURSOR FAST_FORWARD FOR
SELECT QUOTENAME(SCHEMA_NAME(p.schema_id)) + '.' + QUOTENAME(p.name)
FROM sys.procedures p
WHERE p.schema_id = SCHEMA_ID('support')
  AND p.name IN (
      'sp_CreateTicket',
      'sp_AssignTicket',
      'sp_CloseTicket',
      'sp_AddTicketMessage',
      'sp_GetTicketThread',
      'sp_ListOpenTicketsByTier',
      'sp_ListTicketsAssignedTo',
      'sp_GetTicketById'
  );

OPEN proc_cursor;
FETCH NEXT FROM proc_cursor INTO @proc;

WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC('DROP PROCEDURE ' + @proc + ';');
    FETCH NEXT FROM proc_cursor INTO @proc;
END

CLOSE proc_cursor;
DEALLOCATE proc_cursor;
GO

/* =========================
   D) Drop trigger + tables (FK-safe order)
   ========================= */
IF OBJECT_ID('support.TR_Tickets_SetUpdatedAt', 'TR') IS NOT NULL
    DROP TRIGGER support.TR_Tickets_SetUpdatedAt;
GO

IF OBJECT_ID('support.MessageAttachments', 'U') IS NOT NULL DROP TABLE support.MessageAttachments;
GO
IF OBJECT_ID('support.Messages', 'U') IS NOT NULL DROP TABLE support.Messages;
GO
IF OBJECT_ID('support.Tickets', 'U') IS NOT NULL DROP TABLE support.Tickets;
GO
IF OBJECT_ID('support.Channels', 'U') IS NOT NULL DROP TABLE support.Channels;
GO
IF OBJECT_ID('support.Users', 'U') IS NOT NULL DROP TABLE support.Users;
GO
IF OBJECT_ID('support.Guilds', 'U') IS NOT NULL DROP TABLE support.Guilds;
GO

/* =========================
   E) Create tables
   ========================= */

-- Guilds
CREATE TABLE support.Guilds (
    GuildID     BIGINT        NOT NULL,
    GuildName   NVARCHAR(200) NULL,
    CreatedAt   DATETIME2(0)  NOT NULL CONSTRAINT DF_Guilds_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_Guilds PRIMARY KEY CLUSTERED (GuildID)
);
GO

-- Users
CREATE TABLE support.Users (
    UserID      BIGINT         NOT NULL,
    Username    NVARCHAR(100)  NULL,
    DisplayName NVARCHAR(100)  NULL,
    CreatedAt   DATETIME2(0)   NOT NULL CONSTRAINT DF_Users_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_Users PRIMARY KEY CLUSTERED (UserID)
);
GO

-- Channels (FK -> Guilds)
CREATE TABLE support.Channels (
    ChannelID    BIGINT        NOT NULL,
    GuildID      BIGINT        NOT NULL,
    ChannelName  NVARCHAR(200) NULL,
    CreatedAt    DATETIME2(0)  NOT NULL CONSTRAINT DF_Channels_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_Channels PRIMARY KEY CLUSTERED (ChannelID),
    CONSTRAINT FK_Channels_Guilds FOREIGN KEY (GuildID)
        REFERENCES support.Guilds(GuildID)
        ON DELETE CASCADE
);
GO

-- Tickets (FK -> Guilds, Channels, Users)
CREATE TABLE support.Tickets (
    TicketID         BIGINT IDENTITY(1,1) NOT NULL,
    CreatedByUserID  BIGINT NOT NULL,
    GuildID          BIGINT NOT NULL,
    ChannelID        BIGINT NOT NULL,

    Tier             TINYINT NOT NULL CONSTRAINT DF_Tickets_Tier DEFAULT (1),
    IsOpen           BIT     NOT NULL CONSTRAINT DF_Tickets_IsOpen DEFAULT (1),
    AssignedToUserID BIGINT  NULL,

    Title            NVARCHAR(200) NULL,
    CreatedAt        DATETIME2(0)  NOT NULL CONSTRAINT DF_Tickets_CreatedAt DEFAULT (SYSUTCDATETIME()),
    UpdatedAt        DATETIME2(0)  NOT NULL CONSTRAINT DF_Tickets_UpdatedAt DEFAULT (SYSUTCDATETIME()),
    ClosedAt         DATETIME2(0)  NULL,

    CONSTRAINT PK_Tickets PRIMARY KEY CLUSTERED (TicketID),

    CONSTRAINT FK_Tickets_Guilds FOREIGN KEY (GuildID) REFERENCES support.Guilds(GuildID),
    CONSTRAINT FK_Tickets_Channels FOREIGN KEY (ChannelID) REFERENCES support.Channels(ChannelID),
    CONSTRAINT FK_Tickets_CreatedByUser FOREIGN KEY (CreatedByUserID) REFERENCES support.Users(UserID),
    CONSTRAINT FK_Tickets_AssignedToUser FOREIGN KEY (AssignedToUserID) REFERENCES support.Users(UserID),

    CONSTRAINT CK_Tickets_Tier CHECK (Tier BETWEEN 1 AND 5)
);
GO

-- Messages (FK -> Tickets, Guilds, Channels, Users, Messages self)
CREATE TABLE support.Messages (
    MessageID        BIGINT IDENTITY(1,1) NOT NULL,
    TicketID         BIGINT NOT NULL,

    GuildID          BIGINT NOT NULL,
    ChannelID        BIGINT NOT NULL,
    UserID           BIGINT NOT NULL,

    [Text]           NVARCHAR(MAX) NOT NULL,
    ParentMessageID  BIGINT NULL,
    CreatedAt        DATETIME2(0)  NOT NULL CONSTRAINT DF_Messages_CreatedAt DEFAULT (SYSUTCDATETIME()),

    CONSTRAINT PK_Messages PRIMARY KEY CLUSTERED (MessageID),

    CONSTRAINT FK_Messages_Tickets FOREIGN KEY (TicketID)
        REFERENCES support.Tickets(TicketID)
        ON DELETE CASCADE,

    CONSTRAINT FK_Messages_Guilds FOREIGN KEY (GuildID) REFERENCES support.Guilds(GuildID),
    CONSTRAINT FK_Messages_Channels FOREIGN KEY (ChannelID) REFERENCES support.Channels(ChannelID),
    CONSTRAINT FK_Messages_Users FOREIGN KEY (UserID) REFERENCES support.Users(UserID),

    CONSTRAINT FK_Messages_Parent FOREIGN KEY (ParentMessageID) REFERENCES support.Messages(MessageID)
);
GO

-- MessageAttachments (FK -> Messages)
CREATE TABLE support.MessageAttachments (
    AttachmentID  BIGINT IDENTITY(1,1) NOT NULL,
    MessageID     BIGINT NOT NULL,
    FileUrl       NVARCHAR(2048) NOT NULL,
    FileName      NVARCHAR(255)  NULL,
    ContentType   NVARCHAR(100)  NULL,
    UploadedAt    DATETIME2(0)   NOT NULL CONSTRAINT DF_Attachments_UploadedAt DEFAULT (SYSUTCDATETIME()),

    CONSTRAINT PK_MessageAttachments PRIMARY KEY CLUSTERED (AttachmentID),

    CONSTRAINT FK_Attachments_Messages FOREIGN KEY (MessageID)
        REFERENCES support.Messages(MessageID)
        ON DELETE CASCADE
);
GO

/* =========================
   F) Indexes + Trigger
   ========================= */

CREATE INDEX IX_Tickets_IsOpen_Tier ON support.Tickets (IsOpen, Tier);
CREATE INDEX IX_Tickets_AssignedTo  ON support.Tickets (AssignedToUserID) WHERE AssignedToUserID IS NOT NULL;
CREATE INDEX IX_Messages_Ticket_CreatedAt ON support.Messages (TicketID, CreatedAt);
CREATE INDEX IX_Attachments_MessageID ON support.MessageAttachments (MessageID);
GO

CREATE TRIGGER support.TR_Tickets_SetUpdatedAt
ON support.Tickets
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE t
    SET UpdatedAt = SYSUTCDATETIME()
    FROM support.Tickets t
    INNER JOIN inserted i ON t.TicketID = i.TicketID;
END
GO

/* =========================
   G) Stored Procedures
   ========================= */

-- CreateTicket
CREATE PROCEDURE support.sp_CreateTicket
    @CreatedByUserID BIGINT,
    @GuildID         BIGINT,
    @ChannelID       BIGINT,
    @Tier            TINYINT = 1,
    @Title           NVARCHAR(200) = NULL,
    @InitialMessage  NVARCHAR(MAX) = NULL,
    @NewTicketID     BIGINT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        IF @Tier NOT BETWEEN 1 AND 5
            THROW 50001, 'Tier must be between 1 and 5.', 1;

        IF NOT EXISTS (SELECT 1 FROM support.Users WHERE UserID = @CreatedByUserID)
            THROW 50002, 'CreatedByUserID does not exist in Users.', 1;

        IF NOT EXISTS (SELECT 1 FROM support.Guilds WHERE GuildID = @GuildID)
            THROW 50003, 'GuildID does not exist in Guilds.', 1;

        IF NOT EXISTS (SELECT 1 FROM support.Channels WHERE ChannelID = @ChannelID AND GuildID = @GuildID)
            THROW 50004, 'ChannelID does not exist in Channels for this GuildID.', 1;

        BEGIN TRAN;

        INSERT INTO support.Tickets
            (CreatedByUserID, GuildID, ChannelID, Tier, IsOpen, AssignedToUserID, Title)
        VALUES
            (@CreatedByUserID, @GuildID, @ChannelID, @Tier, 1, NULL, @Title);

        SET @NewTicketID = SCOPE_IDENTITY();

        IF @InitialMessage IS NOT NULL AND LEN(@InitialMessage) > 0
        BEGIN
            INSERT INTO support.Messages
                (TicketID, GuildID, ChannelID, UserID, [Text], ParentMessageID)
            VALUES
                (@NewTicketID, @GuildID, @ChannelID, @CreatedByUserID, @InitialMessage, NULL);
        END

        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        THROW;
    END CATCH
END;
GO

-- AssignTicket
CREATE PROCEDURE support.sp_AssignTicket
    @TicketID         BIGINT,
    @AssignedToUserID BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM support.Users WHERE UserID = @AssignedToUserID)
            THROW 50011, 'AssignedToUserID does not exist in Users.', 1;

        IF NOT EXISTS (SELECT 1 FROM support.Tickets WHERE TicketID = @TicketID)
            THROW 50012, 'TicketID does not exist.', 1;

        UPDATE support.Tickets
        SET AssignedToUserID = @AssignedToUserID
        WHERE TicketID = @TicketID;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

-- CloseTicket
CREATE PROCEDURE support.sp_CloseTicket
    @TicketID BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM support.Tickets WHERE TicketID = @TicketID)
            THROW 50021, 'TicketID does not exist.', 1;

        UPDATE support.Tickets
        SET IsOpen = 0,
            ClosedAt = SYSUTCDATETIME()
        WHERE TicketID = @TicketID;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

-- AddTicketMessage
CREATE PROCEDURE support.sp_AddTicketMessage
    @TicketID        BIGINT,
    @GuildID         BIGINT,
    @ChannelID       BIGINT,
    @UserID          BIGINT,
    @Text            NVARCHAR(MAX),
    @ParentMessageID BIGINT = NULL,
    @NewMessageID    BIGINT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        IF @Text IS NULL OR LEN(@Text) = 0
            THROW 50031, 'Message text cannot be empty.', 1;

        IF NOT EXISTS (SELECT 1 FROM support.Users WHERE UserID = @UserID)
            THROW 50032, 'UserID does not exist in Users.', 1;

        IF NOT EXISTS (SELECT 1 FROM support.Tickets WHERE TicketID = @TicketID)
            THROW 50033, 'TicketID does not exist.', 1;

        IF NOT EXISTS (
            SELECT 1
            FROM support.Tickets
            WHERE TicketID = @TicketID AND GuildID = @GuildID AND ChannelID = @ChannelID
        )
            THROW 50034, 'TicketID does not match the provided GuildID/ChannelID.', 1;

        IF @ParentMessageID IS NOT NULL
        BEGIN
            IF NOT EXISTS (
                SELECT 1
                FROM support.Messages
                WHERE MessageID = @ParentMessageID AND TicketID = @TicketID
            )
                THROW 50035, 'ParentMessageID does not exist for this TicketID.', 1;
        END

        INSERT INTO support.Messages
            (TicketID, GuildID, ChannelID, UserID, [Text], ParentMessageID)
        VALUES
            (@TicketID, @GuildID, @ChannelID, @UserID, @Text, @ParentMessageID);

        SET @NewMessageID = SCOPE_IDENTITY();
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

-- GetTicketThread (3 result sets: ticket header, messages, attachments)
CREATE PROCEDURE support.sp_GetTicketThread
    @TicketID BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM support.Tickets WHERE TicketID = @TicketID)
            THROW 50041, 'TicketID does not exist.', 1;

        -- 1) Ticket header
        SELECT
            t.TicketID,
            t.CreatedByUserID,
            u1.Username        AS CreatedByUsername,
            t.GuildID,
            g.GuildName,
            t.ChannelID,
            c.ChannelName,
            t.Tier,
            t.IsOpen,
            t.AssignedToUserID,
            u2.Username        AS AssignedToUsername,
            t.Title,
            t.CreatedAt,
            t.UpdatedAt,
            t.ClosedAt
        FROM support.Tickets t
        LEFT JOIN support.Users u1 ON u1.UserID = t.CreatedByUserID
        LEFT JOIN support.Users u2 ON u2.UserID = t.AssignedToUserID
        LEFT JOIN support.Guilds g ON g.GuildID = t.GuildID
        LEFT JOIN support.Channels c ON c.ChannelID = t.ChannelID
        WHERE t.TicketID = @TicketID;

        -- 2) Messages
        SELECT
            m.MessageID,
            m.TicketID,
            m.UserID,
            u.Username AS Username,
            m.[Text],
            m.ParentMessageID,
            m.CreatedAt
        FROM support.Messages m
        LEFT JOIN support.Users u ON u.UserID = m.UserID
        WHERE m.TicketID = @TicketID
        ORDER BY m.CreatedAt ASC, m.MessageID ASC;

        -- 3) Attachments
        SELECT
            a.AttachmentID,
            a.MessageID,
            a.FileUrl,
            a.FileName,
            a.ContentType,
            a.UploadedAt
        FROM support.MessageAttachments a
        INNER JOIN support.Messages m ON m.MessageID = a.MessageID
        WHERE m.TicketID = @TicketID
        ORDER BY a.UploadedAt ASC, a.AttachmentID ASC;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

-- ListOpenTicketsByTier
CREATE PROCEDURE support.sp_ListOpenTicketsByTier
    @GuildID   BIGINT = NULL,
    @ChannelID BIGINT = NULL,
    @Tier      TINYINT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        SELECT
            t.TicketID,
            t.GuildID,
            g.GuildName,
            t.ChannelID,
            c.ChannelName,
            t.Tier,
            t.IsOpen,
            t.AssignedToUserID,
            u2.Username AS AssignedToUsername,
            t.Title,
            t.CreatedAt,
            t.UpdatedAt
        FROM support.Tickets t
        LEFT JOIN support.Guilds g   ON g.GuildID = t.GuildID
        LEFT JOIN support.Channels c ON c.ChannelID = t.ChannelID
        LEFT JOIN support.Users u2   ON u2.UserID = t.AssignedToUserID
        WHERE t.IsOpen = 1
          AND (@GuildID IS NULL OR t.GuildID = @GuildID)
          AND (@ChannelID IS NULL OR t.ChannelID = @ChannelID)
          AND (@Tier IS NULL OR t.Tier = @Tier)
        ORDER BY t.Tier DESC, t.CreatedAt ASC;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

-- ListTicketsAssignedTo
CREATE PROCEDURE support.sp_ListTicketsAssignedTo
    @AssignedToUserID BIGINT,
    @OpenOnly BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM support.Users WHERE UserID = @AssignedToUserID)
            THROW 50061, 'AssignedToUserID does not exist in Users.', 1;

        SELECT
            t.TicketID,
            t.GuildID,
            t.ChannelID,
            t.Tier,
            t.IsOpen,
            t.Title,
            t.CreatedAt,
            t.UpdatedAt,
            t.ClosedAt
        FROM support.Tickets t
        WHERE t.AssignedToUserID = @AssignedToUserID
          AND (@OpenOnly = 0 OR t.IsOpen = 1)
        ORDER BY t.IsOpen DESC, t.Tier DESC, t.CreatedAt ASC;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

-- GetTicketById
CREATE PROCEDURE support.sp_GetTicketById
    @TicketID BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM support.Tickets WHERE TicketID = @TicketID)
            THROW 50071, 'TicketID does not exist.', 1;

        SELECT
            t.TicketID,
            t.CreatedByUserID,
            t.GuildID,
            t.ChannelID,
            t.Tier,
            t.IsOpen,
            t.AssignedToUserID,
            t.Title,
            t.CreatedAt,
            t.UpdatedAt,
            t.ClosedAt
        FROM support.Tickets t
        WHERE t.TicketID = @TicketID;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

/* =========================
   H) Seed demo data (idempotent)
   ========================= */
IF NOT EXISTS (SELECT 1 FROM support.Guilds WHERE GuildID = 1)
    INSERT INTO support.Guilds (GuildID, GuildName) VALUES (1, 'Demo Guild');

IF NOT EXISTS (SELECT 1 FROM support.Channels WHERE ChannelID = 10)
    INSERT INTO support.Channels (ChannelID, GuildID, ChannelName) VALUES (10, 1, 'support');

IF NOT EXISTS (SELECT 1 FROM support.Users WHERE UserID = 100)
    INSERT INTO support.Users (UserID, Username, DisplayName) VALUES (100, 'arnav', 'Arnav');

IF NOT EXISTS (SELECT 1 FROM support.Users WHERE UserID = 200)
    INSERT INTO support.Users (UserID, Username, DisplayName) VALUES (200, 'agent1', 'Support Agent');
GO

/* =========================
   I) Quick end-to-end test
   ========================= */
DECLARE @NewTicketID BIGINT;

EXEC support.sp_CreateTicket
    @CreatedByUserID = 100,
    @GuildID = 1,
    @ChannelID = 10,
    @Tier = 2,
    @Title = N'Cannot access email',
    @InitialMessage = N'Hi, my email is locked out.',
    @NewTicketID = @NewTicketID OUTPUT;

PRINT 'Created TicketID = ' + CAST(@NewTicketID AS NVARCHAR(30));

-- Add an agent reply
DECLARE @NewMessageID BIGINT;
EXEC support.sp_AddTicketMessage
    @TicketID = @NewTicketID,
    @GuildID = 1,
    @ChannelID = 10,
    @UserID = 200,
    @Text = N'We are investigating this now.',
    @ParentMessageID = NULL,
    @NewMessageID = @NewMessageID OUTPUT;

PRINT 'Created MessageID = ' + CAST(@NewMessageID AS NVARCHAR(30));

-- Read the thread (returns 3 result sets)
EXEC support.sp_GetTicketThread @TicketID = @NewTicketID;

-- List open tickets by tier
EXEC support.sp_ListOpenTicketsByTier @GuildID = 1, @Tier = 2;

-- Show created objects (quick proof)
SELECT s.name AS [Schema], t.name AS [Table]
FROM sys.tables t JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE s.name = 'support'
ORDER BY t.name;

SELECT name AS [Procedure]
FROM sys.procedures
WHERE schema_id = SCHEMA_ID('support')
ORDER BY name;
GO