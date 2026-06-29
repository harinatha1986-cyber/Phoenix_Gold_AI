//+------------------------------------------------------------------+
//|                                                      Reports.mqh |
//|                                  Copyright 2026, Phoenix Gold AI |
//|                                       https://www.google.com/    |
//|                                                                  |
//| Generates advanced performance reports by parsing the trade      |
//| history database and calculating key institutional metrics.      |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Phoenix Gold AI"
#property link      "https://www.google.com/"
#property version   "1.00"
#property once

#include "Utilities.mqh"
#include "Logger.mqh"

//+------------------------------------------------------------------+
//| Class CReports                                                   |
//| Computes and writes detailed EA stats to a report file           |
//+------------------------------------------------------------------+
class CReports
{
private:
   string   m_symbol;
   ulong    m_magic;
   string   m_reports_dir;

public:
            CReports();
           ~CReports() {}
           
   // Initialize parameters
   void     Init(const string symbol, const ulong magic);
   
   // Scan history and generate TXT report file
   bool     GeneratePerformanceReport(const string custom_name="");
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CReports::CReports() : m_symbol(""),
                       m_magic(0),
                       m_reports_dir("PhoenixGoldAI_Reports")
{
   if(!FolderCreate(m_reports_dir))
   {
      Print("[PhoenixGoldAI] [WARNING] Reports directory already exists or failed to create: " + m_reports_dir);
   }
}

//+------------------------------------------------------------------+
//| Init                                                             |
//+------------------------------------------------------------------+
void CReports::Init(const string symbol, const ulong magic)
{
   m_symbol = symbol;
   m_magic = magic;
}

//+------------------------------------------------------------------+
//| GeneratePerformanceReport                                        |
//+------------------------------------------------------------------+
bool CReports::GeneratePerformanceReport(const string custom_name="")
{
   if(!HistorySelect(0, TimeCurrent()))
   {
      Logger.Warning("Could not query account history for reports.");
      return false;
   }
   
   // Statistics variables
   int total_trades = 0;
   int wins = 0;
   int losses = 0;
   double net_profit = 0.0;
   double gross_profit = 0.0;
   double gross_loss = 0.0;
   
   double max_win = 0.0;
   double max_loss = 0.0;
   
   int consecutive_wins = 0;
   int consecutive_losses = 0;
   int max_consec_wins = 0;
   int max_consec_losses = 0;
   
   int deals_cnt = HistoryDealsTotal();
   
   for(int i = 0; i < deals_cnt; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket <= 0) continue;
      
      // Filter by magic number and symbol
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != m_magic ||
         HistoryDealGetString(ticket, DEAL_SYMBOL) != m_symbol)
      {
         continue;
      }
      
      long type = HistoryDealGetInteger(ticket, DEAL_TYPE);
      if(type != DEAL_TYPE_BUY && type != DEAL_TYPE_SELL)
      {
         continue; // Exclude deposits/adjustments
      }
      
      long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      // We evaluate closed trade metrics when position is exited (DEAL_ENTRY_OUT, DEAL_ENTRY_INOUT)
      if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT || entry == DEAL_ENTRY_OUT_BY)
      {
         double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT) +
                        HistoryDealGetDouble(ticket, DEAL_COMMISSION) +
                        HistoryDealGetDouble(ticket, DEAL_SWAP);
                        
         total_trades++;
         net_profit += profit;
         
         if(profit >= 0.0)
         {
            wins++;
            gross_profit += profit;
            if(profit > max_win) max_win = profit;
            
            consecutive_wins++;
            if(consecutive_wins > max_consec_wins) max_consec_wins = consecutive_wins;
            consecutive_losses = 0; // reset
         }
         else
         {
            losses++;
            gross_loss += MathAbs(profit);
            if(MathAbs(profit) > max_loss) max_loss = MathAbs(profit);
            
            consecutive_losses++;
            if(consecutive_losses > max_consec_losses) max_consec_losses = consecutive_losses;
            consecutive_wins = 0; // reset
         }
      }
   }
   
   // Calculations
   double win_rate = (total_trades > 0) ? ((double)wins / total_trades) * 100.0 : 0.0;
   double profit_factor = (gross_loss > 0.0) ? (gross_profit / gross_loss) : gross_profit;
   double avg_win = (wins > 0) ? (gross_profit / wins) : 0.0;
   double avg_loss = (losses > 0) ? (gross_loss / losses) : 0.0;
   
   // Write Report file
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   
   string filename;
   if(custom_name != "")
   {
      filename = StringFormat("%s\\%s", m_reports_dir, custom_name);
   }
   else
   {
      filename = StringFormat("%s\\report_%04d%02d%02d_%02d%02d.txt", 
         m_reports_dir, dt.year, dt.mon, dt.day, dt.hour, dt.min);
   }
   
   int file_handle = FileOpen(filename, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(file_handle == INVALID_HANDLE)
   {
      Logger.Error("Failed to create performance report file: " + filename);
      return false;
   }
   
   // Format content
   string c = "============================================================\n";
   c += "              PHOENIX GOLD AI PERFORMANCE REPORT\n";
   c += "============================================================\n";
   c += StringFormat("Symbol:            %s\n", m_symbol);
   c += StringFormat("Magic Number:      %d\n", m_magic);
   c += StringFormat("Report Time:       %s\n\n", TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS));
   
   c += "------------------------- RESULTS -------------------------\n";
   c += StringFormat("Net Profit:        $%.2f\n", net_profit);
   c += StringFormat("Gross Profit:      $%.2f\n", gross_profit);
   c += StringFormat("Gross Loss:        $%.2f\n", gross_loss);
   c += StringFormat("Profit Factor:     %.2f\n", profit_factor);
   c += StringFormat("Total Trades:      %d\n", total_trades);
   c += StringFormat("Winning Trades:    %d (%.2f%%)\n", wins, win_rate);
   c += StringFormat("Losing Trades:     %d (%.2f%%)\n\n", losses, (total_trades > 0) ? 100.0 - win_rate : 0.0);
   
   c += "------------------- PERFORMANCE RATIOS --------------------\n";
   c += StringFormat("Average Win:       $%.2f\n", avg_win);
   c += StringFormat("Average Loss:      $%.2f\n", avg_loss);
   c += StringFormat("Largest Win:       $%.2f\n", max_win);
   c += StringFormat("Largest Loss:      $%.2f\n", max_loss);
   c += StringFormat("Max Consec Wins:   %d\n", max_consec_wins);
   c += StringFormat("Max Consec Losses: %d\n", max_consec_losses);
   c += "============================================================\n";
   
   FileWriteString(file_handle, c);
   FileClose(file_handle);
   
   Logger.Info("Performance report written successfully: " + filename);
   return true;
}
