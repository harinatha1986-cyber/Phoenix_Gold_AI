//+------------------------------------------------------------------+
//|                                                       Logger.mqh |
//|                                  Copyright 2026, Phoenix Gold AI |
//|                                       https://www.google.com/    |
//|                                                                  |
//| A world-class, production-quality logger for MetaTrader 5 EAs.   |
//| Handles daily CSV rotation, thread safety (via single-unit check)|
//| and formatted terminal logging.                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Phoenix Gold AI"
#property link      "https://www.google.com/"
#property version   "1.00"
#property once

//+------------------------------------------------------------------+
//| Class CLogger                                                    |
//| Handles CSV logging, file rotation, and console reporting        |
//+------------------------------------------------------------------+
class CLogger
{
private:
   int            m_file_handle;     // Handle to the open CSV log file
   datetime       m_current_date;    // Current date representation for file rotation
   string         m_log_dir;         // Directory where logs are saved
   string         m_file_path;       // Cached full file path of current log
   
   // Close the active file handle
   void           CloseFile();
   
   // Initialize/Rotate file handles daily
   bool           InitFile();
   
   // Internal log dispatcher
   void           Log(const string level, const string message);

public:
                  CLogger();
                 ~CLogger();
                 
   // Public logging interfaces
   void           Info(const string message);
   void           Warning(const string message);
   void           Error(const string message);
   void           Trade(const string message);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CLogger::CLogger() : m_file_handle(INVALID_HANDLE),
                     m_current_date(0),
                     m_log_dir("PhoenixGoldAI_Logs"),
                     m_file_path("")
{
   // Create the logs folder inside MQL5/Files/
   if(!FolderCreate(m_log_dir))
   {
      Print("[PhoenixGoldAI] [WARNING] Failed to create folder or it already exists: " + m_log_dir);
   }
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CLogger::~CLogger()
{
   CloseFile();
}

//+------------------------------------------------------------------+
//| CloseFile                                                        |
//+------------------------------------------------------------------+
void CLogger::CloseFile()
{
   if(m_file_handle != INVALID_HANDLE)
   {
      FileClose(m_file_handle);
      m_file_handle = INVALID_HANDLE;
   }
}

//+------------------------------------------------------------------+
//| InitFile                                                         |
//+------------------------------------------------------------------+
bool CLogger::InitFile()
{
   datetime now = TimeCurrent();
   
   // Calculate start of day (00:00:00)
   MqlDateTime dt;
   TimeToStruct(now, dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   datetime day_start = StructToTime(dt);
   
   // If the day hasn't changed and the file is already open, return true
   if(m_file_handle != INVALID_HANDLE && day_start == m_current_date)
   {
      return true;
   }
   
   // Close current file to prepare for rotation
   CloseFile();
   
   m_current_date = day_start;
   
   // Generate filename: PhoenixGoldAI_Logs/log_YYYY_MM_DD.csv
   m_file_path = StringFormat("%s\\log_%04d_%02d_%02d.csv", m_log_dir, dt.year, dt.mon, dt.day);
   
   // Open the daily log file (Read & Write with Share Read permissions)
   m_file_handle = FileOpen(m_file_path, FILE_WRITE | FILE_READ | FILE_CSV | FILE_ANSI | FILE_SHARE_READ, ',');
   if(m_file_handle == INVALID_HANDLE)
   {
      Print("[PhoenixGoldAI] [ERROR] Failed to open log file: " + m_file_path + ". Error code: " + (string)GetLastError());
      return false;
   }
   
   // Write CSV header if the file is empty/new
   if(FileSize(m_file_handle) == 0)
   {
      FileWrite(m_file_handle, "Timestamp", "Level", "Message");
   }
   else
   {
      // Append to the end of the existing file
      FileSeek(m_file_handle, 0, SEEK_END);
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Log                                                              |
//+------------------------------------------------------------------+
void CLogger::Log(const string level, const string message)
{
   datetime now = TimeCurrent();
   string timestamp = TimeToString(now, TIME_DATE | TIME_SECONDS);
   
   // Print formatted output to the MetaTrader 5 Terminal Journal
   Print(StringFormat("[PhoenixGoldAI] [%s] %s", level, message));
   
   // Try to write to CSV log file
   if(InitFile())
   {
      FileWrite(m_file_handle, timestamp, level, message);
      FileFlush(m_file_handle); // Ensure data is immediately flushed to disk
   }
}

//+------------------------------------------------------------------+
//| Info                                                             |
//+------------------------------------------------------------------+
void CLogger::Info(const string message)
{
   Log("INFO", message);
}

//+------------------------------------------------------------------+
//| Warning                                                          |
//+------------------------------------------------------------------+
void CLogger::Warning(const string message)
{
   Log("WARNING", message);
}

//+------------------------------------------------------------------+
//| Error                                                            |
//+------------------------------------------------------------------+
void CLogger::Error(const string message)
{
   Log("ERROR", message);
}

//+------------------------------------------------------------------+
//| Trade                                                            |
//+------------------------------------------------------------------+
void CLogger::Trade(const string message)
{
   Log("TRADE", message);
}

// Global logger instance for convenience
CLogger Logger;
