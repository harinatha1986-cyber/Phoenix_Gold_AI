//+------------------------------------------------------------------+
//|                                                   RiskManager.mqh |
//|                                  Copyright 2026, Phoenix Gold AI |
//|                                       https://www.google.com/    |
//|                                                                  |
//| Handles account safety, daily/weekly/monthly drawdowns, maximum   |
//| trades per day, risk-per-trade verification, and margin checks.   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Phoenix Gold AI"
#property link      "https://www.google.com/"
#property version   "1.00"
#property once

#include "Utilities.mqh"
#include "Logger.mqh"

//+------------------------------------------------------------------+
//| Class CRiskManager                                               |
//| Enforces risk parameters, drawdown caps, and trade limitations   |
//+------------------------------------------------------------------+
class CRiskManager
{
private:
   // Configurable Risk Settings
   double         m_max_daily_dd;       // Maximum daily drawdown % (e.g. 5.0)
   double         m_max_weekly_dd;      // Maximum weekly drawdown % (e.g. 8.0)
   double         m_max_monthly_dd;     // Maximum monthly drawdown % (e.g. 10.0)
   int            m_max_trades_per_day; // Maximum entry trades per day
   double         m_max_exposure_lots;  // Maximum total lot exposure across all open positions
   double         m_min_margin_level;   // Minimum free margin level % (e.g. 200.0)
   
   // Roadmap enhancements
   ulong          m_magic;
   int            m_max_consec_losses;
   double         m_max_float_loss_pct;
   
   // Internal history query helper
   double         GetStartingBalance(const datetime start_time);
   bool           CheckConsecutiveLosses(const string symbol);
   bool           IsFloatingLossExceeded(double &out_current_fl_pct);

public:
                  CRiskManager();
                 ~CRiskManager() {}
                 
   // Configuration setters
   void           SetLimits(const double daily_dd, const double weekly_dd, const double monthly_dd,
                            const int max_trades, const double max_exposure, const double min_margin);
   void           ConfigureRoadmapLimits(const ulong magic, const int max_consec_losses, const double max_float_loss_pct);

   // Risk checks
   bool           IsTradingAllowed(const string symbol);
   bool           CheckDailyDrawdown(double &out_current_dd);
   bool           CheckWeeklyDrawdown(double &out_current_dd);
   bool           CheckMonthlyDrawdown(double &out_current_dd);
   int            GetTradesCountToday();
   double         GetCurrentExposure();
   
   // Property getters
   double         GetMaxDailyDrawdown()      const { return m_max_daily_dd; }
   double         GetMaxWeeklyDrawdown()     const { return m_max_weekly_dd; }
   double         GetMaxMonthlyDrawdown()    const { return m_max_monthly_dd; }
   int            GetMaxTradesPerDay()       const { return m_max_trades_per_day; }
   double         GetMaxExposure()           const { return m_max_exposure_lots; }
   int            GetMaxConsecutiveLosses()  const { return m_max_consec_losses; }
   double         GetMaxFloatingLossPct()    const { return m_max_float_loss_pct; }
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CRiskManager::CRiskManager() : m_max_daily_dd(5.0),
                               m_max_weekly_dd(8.0),
                               m_max_monthly_dd(10.0),
                               m_max_trades_per_day(5),
                               m_max_exposure_lots(2.0),
                               m_min_margin_level(200.0),
                               m_magic(991199),
                               m_max_consec_losses(3),
                               m_max_float_loss_pct(2.0)
{
}

//+------------------------------------------------------------------+
//| ConfigureRoadmapLimits                                           |
//+------------------------------------------------------------------+
void CRiskManager::ConfigureRoadmapLimits(const ulong magic, const int max_consec_losses, const double max_float_loss_pct)
{
   m_magic = magic;
   m_max_consec_losses = max_consec_losses;
   m_max_float_loss_pct = max_float_loss_pct;
   
   Logger.Info(StringFormat("Roadmap Risk limits configured: Magic %lld, MaxConsecLosses %d, MaxFloatLoss%% %.2f%%",
      m_magic, m_max_consec_losses, m_max_float_loss_pct));
}

//+------------------------------------------------------------------+
//| SetLimits                                                        |
//+------------------------------------------------------------------+
void CRiskManager::SetLimits(const double daily_dd, const double weekly_dd, const double monthly_dd,
                            const int max_trades, const double max_exposure, const double min_margin)
{
   m_max_daily_dd = daily_dd;
   m_max_weekly_dd = weekly_dd;
   m_max_monthly_dd = monthly_dd;
   m_max_trades_per_day = max_trades;
   m_max_exposure_lots = max_exposure;
   m_min_margin_level = min_margin;
   
   Logger.Info(StringFormat("Risk limits configured: DailyDD %.2f%%, WeeklyDD %.2f%%, MonthlyDD %.2f%%, MaxTrades %d, MaxExposure %.2f lots",
      m_max_daily_dd, m_max_weekly_dd, m_max_monthly_dd, m_max_trades_per_day, m_max_exposure_lots));
}

//+------------------------------------------------------------------+
//| GetStartingBalance                                               |
//+------------------------------------------------------------------+
double CRiskManager::GetStartingBalance(const datetime start_time)
{
   double current_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   datetime now = TimeCurrent();
   
   if(!HistorySelect(start_time, now))
   {
      return current_balance;
   }
   
   double profit = 0.0;
   double deposit_withdrawal = 0.0;
   int total_deals = HistoryDealsTotal();
   
   for(int i = 0; i < total_deals; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket > 0)
      {
         long type = HistoryDealGetInteger(ticket, DEAL_TYPE);
         if(type == DEAL_TYPE_BALANCE)
         {
            deposit_withdrawal += HistoryDealGetDouble(ticket, DEAL_PROFIT);
         }
         else
         {
            long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
            if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT || entry == DEAL_ENTRY_OUT_BY)
            {
               double deal_profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
               double deal_commission = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
               double deal_swap = HistoryDealGetDouble(ticket, DEAL_SWAP);
               profit += (deal_profit + deal_commission + deal_swap);
            }
         }
      }
   }
   
   // Subtract profit and funding actions to reconstruct starting balance
   double starting_balance = current_balance - profit - deposit_withdrawal;
   return (starting_balance > 0.0) ? starting_balance : current_balance;
}

//+------------------------------------------------------------------+
//| CheckDailyDrawdown                                               |
//+------------------------------------------------------------------+
bool CRiskManager::CheckDailyDrawdown(double &out_current_dd)
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime day_start = StructToTime(dt);
   
   double start_bal = GetStartingBalance(day_start);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   if(equity < start_bal)
   {
      out_current_dd = ((start_bal - equity) / start_bal) * 100.0;
      return (out_current_dd < m_max_daily_dd);
   }
   
   out_current_dd = 0.0;
   return true;
}

//+------------------------------------------------------------------+
//| CheckWeeklyDrawdown                                              |
//+------------------------------------------------------------------+
bool CRiskManager::CheckWeeklyDrawdown(double &out_current_dd)
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime day_start = StructToTime(dt);
   
   // Calculate Monday start
   int days_to_subtract = dt.day_of_week - 1;
   if(dt.day_of_week == 0) days_to_subtract = 5; // Sunday
   if(dt.day_of_week == 6) days_to_subtract = 6; // Saturday
   datetime week_start = day_start - (days_to_subtract * 86400);
   
   double start_bal = GetStartingBalance(week_start);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   if(equity < start_bal)
   {
      out_current_dd = ((start_bal - equity) / start_bal) * 100.0;
      return (out_current_dd < m_max_weekly_dd);
   }
   
   out_current_dd = 0.0;
   return true;
}

//+------------------------------------------------------------------+
//| CheckMonthlyDrawdown                                             |
//+------------------------------------------------------------------+
bool CRiskManager::CheckMonthlyDrawdown(double &out_current_dd)
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.day = 1; dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime month_start = StructToTime(dt);
   
   double start_bal = GetStartingBalance(month_start);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   if(equity < start_bal)
   {
      out_current_dd = ((start_bal - equity) / start_bal) * 100.0;
      return (out_current_dd < m_max_monthly_dd);
   }
   
   out_current_dd = 0.0;
   return true;
}

//+------------------------------------------------------------------+
//| GetTradesCountToday                                              |
//+------------------------------------------------------------------+
int CRiskManager::GetTradesCountToday()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime day_start = StructToTime(dt);
   
   if(!HistorySelect(day_start, TimeCurrent()))
   {
      return 0;
   }
   
   int count = 0;
   int total_deals = HistoryDealsTotal();
   
   for(int i = 0; i < total_deals; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket > 0)
      {
         long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
         long type = HistoryDealGetInteger(ticket, DEAL_TYPE);
         if(entry == DEAL_ENTRY_IN && (type == DEAL_TYPE_BUY || type == DEAL_TYPE_SELL))
         {
            count++;
         }
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| GetCurrentExposure                                               |
//+------------------------------------------------------------------+
double CRiskManager::GetCurrentExposure()
{
   double total_lots = 0.0;
   int total_positions = PositionsTotal();
   
   for(int i = 0; i < total_positions; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         total_lots += PositionGetDouble(POSITION_VOLUME);
      }
   }
   return total_lots;
}

//+------------------------------------------------------------------+
//| IsTradingAllowed                                                 |
//+------------------------------------------------------------------+
bool CRiskManager::IsTradingAllowed(const string symbol)
{
   // Check Daily Drawdown
   double daily_dd = 0.0;
   if(!CheckDailyDrawdown(daily_dd))
   {
      Logger.Warning(StringFormat("Trading blocked: Daily drawdown limit reached (%.2f%% / %.2f%%)", daily_dd, m_max_daily_dd));
      return false;
   }
   
   // Check Weekly Drawdown
   double weekly_dd = 0.0;
   if(!CheckWeeklyDrawdown(weekly_dd))
   {
      Logger.Warning(StringFormat("Trading blocked: Weekly drawdown limit reached (%.2f%% / %.2f%%)", weekly_dd, m_max_weekly_dd));
      return false;
   }
   
   // Check Monthly Drawdown
   double monthly_dd = 0.0;
   if(!CheckMonthlyDrawdown(monthly_dd))
   {
      Logger.Warning(StringFormat("Trading blocked: Monthly drawdown limit reached (%.2f%% / %.2f%%)", monthly_dd, m_max_monthly_dd));
      return false;
   }
   
   // Check Daily Max Trades limit
   int trades_today = GetTradesCountToday();
   if(trades_today >= m_max_trades_per_day)
   {
      Logger.Warning(StringFormat("Trading blocked: Max daily trades count reached (%d / %d)", trades_today, m_max_trades_per_day));
      return false;
   }
   
   // Check margin levels
   double margin_level = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   if(margin_level > 0.0 && margin_level < m_min_margin_level)
   {
      Logger.Warning(StringFormat("Trading blocked: Margin level too low (%.2f%% < %.2f%%)", margin_level, m_min_margin_level));
      return false;
   }
   
   // Check Exposure
   double current_lots = GetCurrentExposure();
   if(current_lots >= m_max_exposure_lots)
   {
      Logger.Warning(StringFormat("Trading blocked: Max lot exposure limit reached (%.2f / %.2f lots)", current_lots, m_max_exposure_lots));
      return false;
   }
   
   // Check Consecutive Losses
   if(!CheckConsecutiveLosses(symbol))
   {
      Logger.Warning(StringFormat("Trading blocked: Max consecutive losses reached (%d)", m_max_consec_losses));
      return false;
   }
   
   // Check Floating Loss
   double fl_pct = 0.0;
   if(IsFloatingLossExceeded(fl_pct))
   {
      Logger.Warning(StringFormat("Trading blocked: Max floating loss limit reached (%.2f%% / %.2f%%)", fl_pct, m_max_float_loss_pct));
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| CheckConsecutiveLosses                                           |
//+------------------------------------------------------------------+
bool CRiskManager::CheckConsecutiveLosses(const string symbol)
{
   if(m_max_consec_losses <= 0) return true;
   
   if(!HistorySelect(0, TimeCurrent())) return true;
   
   int consec_losses = 0;
   int total_deals = HistoryDealsTotal();
   
   for(int i = total_deals - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket > 0)
      {
         if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == (long)m_magic &&
            HistoryDealGetString(ticket, DEAL_SYMBOL) == symbol)
         {
            long type = HistoryDealGetInteger(ticket, DEAL_TYPE);
            if(type == DEAL_TYPE_BUY || type == DEAL_TYPE_SELL)
            {
               long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
               if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT || entry == DEAL_ENTRY_OUT_BY)
               {
                  double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT) +
                                 HistoryDealGetDouble(ticket, DEAL_COMMISSION) +
                                 HistoryDealGetDouble(ticket, DEAL_SWAP);
                  if(profit < 0.0)
                  {
                     consec_losses++;
                     if(consec_losses >= m_max_consec_losses)
                     {
                        return false;
                     }
                  }
                  else if(profit > 0.0)
                  {
                     break;
                  }
               }
            }
         }
      }
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| IsFloatingLossExceeded                                           |
//+------------------------------------------------------------------+
bool CRiskManager::IsFloatingLossExceeded(double &out_current_fl_pct)
{
   if(m_max_float_loss_pct <= 0.0) return false;
   
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double profit = AccountInfoDouble(ACCOUNT_PROFIT);
   
   if(profit < 0.0 && balance > 0.0)
   {
      out_current_fl_pct = (MathAbs(profit) / balance) * 100.0;
      return (out_current_fl_pct >= m_max_float_loss_pct);
   }
   
   out_current_fl_pct = 0.0;
   return false;
}
