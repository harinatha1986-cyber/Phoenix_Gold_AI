//+------------------------------------------------------------------+
//|                                                 TradeManager.mqh |
//|                                  Copyright 2026, Phoenix Gold AI |
//|                                       https://www.google.com/    |
//|                                                                  |
//| Coordinates trade execution, order modifications, trailing stops, |
//| break-even points, partial close logic, and broker constraints.  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Phoenix Gold AI"
#property link      "https://www.google.com/"
#property version   "1.00"
#property once

#include <Trade/Trade.mqh>
#include "Utilities.mqh"
#include "Logger.mqh"

//+------------------------------------------------------------------+
//| Class CTradeManager                                              |
//| Handles trade execution and active position modifications        |
//+------------------------------------------------------------------+
class CTradeManager
{
private:
   CTrade         m_trade;              // MQL5 standard trade execution class
   ulong          m_magic_number;       // Magic number for tracking EA orders
   int            m_slippage;           // Allowable slippage in points
   double         m_max_spread;         // Maximum allowable spread in points
   
   // Break Even configuration
   bool           m_use_break_even;
   double         m_be_activation;      // Points in profit before BE triggers
   double         m_be_offset;          // Points above entry for SL buffer
   
   // Trailing Stop configuration
   bool           m_use_trailing;
   double         m_trail_start;        // Points in profit before trailing starts
   double         m_trail_distance;     // SL distance behind price in points
   double         m_trail_step;         // Minimum SL movement step in points
   
   // Partial Close configuration
   bool           m_use_partial;
   double         m_partial_pct;        // Percentage of lot size to close (e.g. 0.50)
   double         m_partial_target_rr;   // Target Risk Reward ratio for partial close (e.g. 1.0)
   
   // Cached list of ticket IDs that have been partially closed
   ulong          m_partially_closed_tickets[];
   int            m_pc_tickets_count;
   
   // Roadmap time exits configuration
   bool           m_use_friday_exit;
   int            m_friday_exit_mins;
   bool           m_use_duration_exit;
   int            m_max_holding_mins;
   
   // Internal state helpers
   bool           IsAlreadyPartiallyClosed(const ulong ticket);
   void           MarkAsPartiallyClosed(const ulong ticket);
   void           SetupFillingMode(const string symbol);
   double         NormalizeVolume(const string symbol, const double volume);

public:
                  CTradeManager();
                 ~CTradeManager() {}
                 
   // Initialize managers
   void           Init(const ulong magic, const int slippage, const double max_spread);
   
   // Configure trade rules
   void           ConfigureBreakEven(const bool use_be, const double activation_pts, const double offset_pts);
   void           ConfigureTrailingStop(const bool use_trail, const double start_pts, const double dist_pts, const double step_pts);
   void           ConfigurePartialClose(const bool use_pc, const double pct, const double target_rr);
   void           ConfigureTimeExit(const bool use_friday, const string friday_time, const bool use_duration, const int max_holding_mins);
   void           CloseAllPositions(const string symbol);
   void           ProcessTimeExits(const string symbol);

   // Order Execution
   bool           OpenBuy(const double lot, const double sl, const double tp, const string comment="");
   bool           OpenSell(const double lot, const double sl, const double tp, const string comment="");
   
   // Position Management
   void           ManageActiveTrades(const string symbol);
   
   // Helper Checks
   bool           IsPositionOpen(const string symbol);
   bool           CheckSpread(const string symbol, double &out_spread);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CTradeManager::CTradeManager() : m_magic_number(991199),
                                 m_slippage(30),
                                 m_max_spread(25.0),
                                 m_use_break_even(true),
                                 m_be_activation(150.0),
                                 m_be_offset(20.0),
                                 m_use_trailing(true),
                                 m_trail_start(200.0),
                                 m_trail_distance(150.0),
                                 m_trail_step(20.0),
                                 m_use_partial(true),
                                 m_partial_pct(0.50),
                                 m_partial_target_rr(1.0),
                                 m_pc_tickets_count(0),
                                 m_use_friday_exit(true),
                                 m_friday_exit_mins(1320), // 22:00
                                 m_use_duration_exit(false),
                                 m_max_holding_mins(1440) // 24 hours
{
   ArrayResize(m_partially_closed_tickets, 0);
}

//+------------------------------------------------------------------+
//| Init                                                             |
//+------------------------------------------------------------------+
void CTradeManager::Init(const ulong magic, const int slippage, const double max_spread)
{
   m_magic_number = magic;
   m_slippage = slippage;
   m_max_spread = max_spread;
   
   m_trade.SetExpertMagicNumber(m_magic_number);
   m_trade.SetDeviationInPoints(m_slippage);
   
   Logger.Info(StringFormat("Trade Manager initialized. MagicNumber=%d, Slippage=%d points, MaxSpread=%.1f points",
      m_magic_number, m_slippage, m_max_spread));
}

//+------------------------------------------------------------------+
//| ConfigureBreakEven                                               |
//+------------------------------------------------------------------+
void CTradeManager::ConfigureBreakEven(const bool use_be, const double activation_pts, const double offset_pts)
{
   m_use_break_even = use_be;
   m_be_activation = activation_pts;
   m_be_offset = offset_pts;
   
   Logger.Info(StringFormat("Break Even Configured: Enabled=%d, Activation=%.1f pts, Offset=%.1f pts",
      m_use_break_even, m_be_activation, m_be_offset));
}

//+------------------------------------------------------------------+
//| ConfigureTrailingStop                                            |
//+------------------------------------------------------------------+
void CTradeManager::ConfigureTrailingStop(const bool use_trail, const double start_pts, const double dist_pts, const double step_pts)
{
   m_use_trailing = use_trail;
   m_trail_start = start_pts;
   m_trail_distance = dist_pts;
   m_trail_step = step_pts;
   
   Logger.Info(StringFormat("Trailing Stop Configured: Enabled=%d, Start=%.1f pts, Distance=%.1f pts, Step=%.1f pts",
      m_use_trailing, m_trail_start, m_trail_distance, m_trail_step));
}

//+------------------------------------------------------------------+
//| ConfigurePartialClose                                            |
//+------------------------------------------------------------------+
void CTradeManager::ConfigurePartialClose(const bool use_pc, const double pct, const double target_rr)
{
   m_use_partial = use_pc;
   m_partial_pct = pct;
   m_partial_target_rr = target_rr;
   
   Logger.Info(StringFormat("Partial Close Configured: Enabled=%d, ClosePct=%.2f%%, TargetRR=%.1f",
      m_use_partial, m_partial_pct * 100.0, m_partial_target_rr));
}

//+------------------------------------------------------------------+
//| SetupFillingMode                                                 |
//+------------------------------------------------------------------+
void CTradeManager::SetupFillingMode(const string symbol)
{
   uint filling = (uint)SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK) != 0)
   {
      m_trade.SetTypeFilling(ORDER_FILLING_FOK);
   }
   else if((filling & SYMBOL_FILLING_IOC) != 0)
   {
      m_trade.SetTypeFilling(ORDER_FILLING_IOC);
   }
   else
   {
      m_trade.SetTypeFilling(ORDER_FILLING_RETURN);
   }
}

//+------------------------------------------------------------------+
//| NormalizeVolume                                                  |
//+------------------------------------------------------------------+
double CTradeManager::NormalizeVolume(const string symbol, const double volume)
{
   double min_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   
   double normalized = MathFloor(volume / step) * step;
   if(normalized < min_lot) normalized = min_lot;
   if(normalized > max_lot) normalized = max_lot;
   
   int decimals = 0;
   double s = step;
   while(s < 1.0) { s *= 10.0; decimals++; }
   
   return NormalizeDouble(normalized, decimals);
}

//+------------------------------------------------------------------+
//| IsAlreadyPartiallyClosed                                         |
//+------------------------------------------------------------------+
bool CTradeManager::IsAlreadyPartiallyClosed(const ulong ticket)
{
   for(int i = 0; i < m_pc_tickets_count; i++)
   {
      if(m_partially_closed_tickets[i] == ticket) return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| MarkAsPartiallyClosed                                            |
//+------------------------------------------------------------------+
void CTradeManager::MarkAsPartiallyClosed(const ulong ticket)
{
   m_pc_tickets_count++;
   ArrayResize(m_partially_closed_tickets, m_pc_tickets_count);
   m_partially_closed_tickets[m_pc_tickets_count - 1] = ticket;
}

//+------------------------------------------------------------------+
//| IsPositionOpen                                                   |
//+------------------------------------------------------------------+
bool CTradeManager::IsPositionOpen(const string symbol)
{
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == symbol && 
            PositionGetInteger(POSITION_MAGIC) == m_magic_number)
         {
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| CheckSpread                                                      |
//+------------------------------------------------------------------+
bool CTradeManager::CheckSpread(const string symbol, double &out_spread)
{
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   
   if(point <= 0.0) return false;
   
   out_spread = (ask - bid) / point;
   return (out_spread <= m_max_spread);
}

//+------------------------------------------------------------------+
//| OpenBuy                                                          |
//+------------------------------------------------------------------+
bool CTradeManager::OpenBuy(const double lot, const double sl, const double tp, const string comment="")
{
   string symbol = Symbol();
   if(IsPositionOpen(symbol))
   {
      Logger.Warning("Order Buy Blocked: Position already exists on this symbol.");
      return false;
   }
   
   double spread = 0.0;
   if(!CheckSpread(symbol, spread))
   {
      Logger.Warning(StringFormat("Order Buy Blocked: Spread (%.1f points) exceeds max threshold (%.1f points)", spread, m_max_spread));
      return false;
   }
   
   SetupFillingMode(symbol);
   double price = SymbolInfoDouble(symbol, SYMBOL_ASK);
   
   // Normalize price inputs
   double norm_sl = CUtilities::NormalizePrice(symbol, sl);
   double norm_tp = CUtilities::NormalizePrice(symbol, tp);
   
   if(m_trade.Buy(lot, symbol, price, norm_sl, norm_tp, comment))
   {
      ulong ticket = m_trade.ResultOrder();
      Logger.Trade(StringFormat("BUY Execution Success: Ticket %lld | Price %.2f | Lot %.2f | SL %.2f | TP %.2f",
         (long)ticket, price, lot, norm_sl, norm_tp));
      return true;
   }
   
   Logger.Error(StringFormat("BUY Execution Failed: Error %d (%s)", m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription()));
   return false;
}

//+------------------------------------------------------------------+
//| OpenSell                                                         |
//+------------------------------------------------------------------+
bool CTradeManager::OpenSell(const double lot, const double sl, const double tp, const string comment="")
{
   string symbol = Symbol();
   if(IsPositionOpen(symbol))
   {
      Logger.Warning("Order Sell Blocked: Position already exists on this symbol.");
      return false;
   }
   
   double spread = 0.0;
   if(!CheckSpread(symbol, spread))
   {
      Logger.Warning(StringFormat("Order Sell Blocked: Spread (%.1f points) exceeds max threshold (%.1f points)", spread, m_max_spread));
      return false;
   }
   
   SetupFillingMode(symbol);
   double price = SymbolInfoDouble(symbol, SYMBOL_BID);
   
   // Normalize price inputs
   double norm_sl = CUtilities::NormalizePrice(symbol, sl);
   double norm_tp = CUtilities::NormalizePrice(symbol, tp);
   
   if(m_trade.Sell(lot, symbol, price, norm_sl, norm_tp, comment))
   {
      ulong ticket = m_trade.ResultOrder();
      Logger.Trade(StringFormat("SELL Execution Success: Ticket %lld | Price %.2f | Lot %.2f | SL %.2f | TP %.2f",
         (long)ticket, price, lot, norm_sl, norm_tp));
      return true;
   }
   
   Logger.Error(StringFormat("SELL Execution Failed: Error %d (%s)", m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription()));
   return false;
}

//+------------------------------------------------------------------+
//| ManageActiveTrades                                               |
//+------------------------------------------------------------------+
void CTradeManager::ManageActiveTrades(const string symbol)
{
   // Process roadmap time exits first
   ProcessTimeExits(symbol);
   
   int total = PositionsTotal();
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      if(PositionGetString(POSITION_SYMBOL) != symbol || PositionGetInteger(POSITION_MAGIC) != m_magic_number)
      {
         continue;
      }
      
      long type = PositionGetInteger(POSITION_TYPE);
      double entry_price = PositionGetDouble(POSITION_PRICE_OPEN);
      double current_sl = PositionGetDouble(POSITION_SL);
      double current_tp = PositionGetDouble(POSITION_TP);
      double volume = PositionGetDouble(POSITION_VOLUME);
      
      // Calculate current trade parameters
      double risk_pts = 0.0;
      if(type == POSITION_TYPE_BUY)
      {
         risk_pts = (entry_price - current_sl) / point;
      }
      else
      {
         risk_pts = (current_sl - entry_price) / point;
      }
      
      if(risk_pts <= 0.0) risk_pts = 100.0; // Fallback
      
      // 1. Partial Close logic
      if(m_use_partial && !IsAlreadyPartiallyClosed(ticket))
      {
         double target_profit_pts = risk_pts * m_partial_target_rr;
         
         bool trigger_pc = false;
         if(type == POSITION_TYPE_BUY && (bid - entry_price) >= target_profit_pts * point)
         {
            trigger_pc = true;
         }
         else if(type == POSITION_TYPE_SELL && (entry_price - ask) >= target_profit_pts * point)
         {
            trigger_pc = true;
         }
         
         if(trigger_pc)
         {
            double close_vol = NormalizeVolume(symbol, volume * m_partial_pct);
            if(close_vol < volume)
            {
                Logger.Info(StringFormat("Executing Partial Close: Ticket %lld | Volume %.2f / %.2f", (long)ticket, close_vol, volume));
                if(m_trade.PositionClosePartial(ticket, close_vol, m_slippage))
                {
                   MarkAsPartiallyClosed(ticket);
                   Logger.Trade(StringFormat("Partial Close Success: Ticket %lld | Closed Volume %.2f", (long)ticket, close_vol));
                   continue; // Re-evaluate on next pass
                }
                else
                {
                   Logger.Error(StringFormat("Partial Close Failed: Ticket %lld", (long)ticket));
                }
            }
         }
      }
      
      // 2. Break Even logic
      if(m_use_break_even)
      {
         bool trigger_be = false;
         double new_sl = 0.0;
         
         if(type == POSITION_TYPE_BUY)
         {
            if((bid - entry_price) >= m_be_activation * point && current_sl < entry_price)
            {
               new_sl = entry_price + (m_be_offset * point);
               trigger_be = true;
            }
         }
         else if(type == POSITION_TYPE_SELL)
         {
            if((entry_price - ask) >= m_be_activation * point && (current_sl > entry_price || current_sl == 0.0))
            {
               new_sl = entry_price - (m_be_offset * point);
               trigger_be = true;
            }
         }
         
         if(trigger_be)
         {
            new_sl = CUtilities::NormalizePrice(symbol, new_sl);
            Logger.Info(StringFormat("Modifying SL to Break Even: Ticket %lld | SL %.2f -> %.2f", (long)ticket, current_sl, new_sl));
            if(!m_trade.PositionModify(ticket, new_sl, current_tp))
            {
               Logger.Error(StringFormat("Break Even Modification Failed: Ticket %lld", (long)ticket));
            }
            continue;
         }
      }
      
      // 3. Trailing Stop logic
      if(m_use_trailing)
      {
         bool trigger_trail = false;
         double new_sl = 0.0;
         
         if(type == POSITION_TYPE_BUY)
         {
            if((bid - entry_price) >= m_trail_start * point)
            {
               double prospective_sl = bid - (m_trail_distance * point);
               // Only move trailing stop UP (never down)
               if(prospective_sl > current_sl + (m_trail_step * point) || current_sl == 0.0)
               {
                  new_sl = prospective_sl;
                  trigger_trail = true;
               }
            }
         }
         else if(type == POSITION_TYPE_SELL)
         {
            if((entry_price - ask) >= m_trail_start * point)
            {
               double prospective_sl = ask + (m_trail_distance * point);
               // Only move trailing stop DOWN (never up)
               if(prospective_sl < current_sl - (m_trail_step * point) || current_sl == 0.0)
               {
                  new_sl = prospective_sl;
                  trigger_trail = true;
               }
            }
         }
         
         if(trigger_trail)
         {
            new_sl = CUtilities::NormalizePrice(symbol, new_sl);
            Logger.Info(StringFormat("Modifying SL via Trailing Stop: Ticket %lld | SL %.2f -> %.2f", (long)ticket, current_sl, new_sl));
            if(!m_trade.PositionModify(ticket, new_sl, current_tp))
            {
               Logger.Error(StringFormat("Trailing Modification Failed: Ticket %lld", (long)ticket));
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| ConfigureTimeExit                                                |
//+------------------------------------------------------------------+
void CTradeManager::ConfigureTimeExit(const bool use_friday, const string friday_time, const bool use_duration, const int max_holding_mins)
{
   m_use_friday_exit = use_friday;
   m_friday_exit_mins = CUtilities::StringToMinutes(friday_time);
   m_use_duration_exit = use_duration;
   m_max_holding_mins = max_holding_mins;
   
   if(m_friday_exit_mins == -1) m_friday_exit_mins = 1320; // 22:00 fallback
   
   Logger.Info(StringFormat("Time Exit Configured: FridayExit=%d at %s (%d mins), MaxDurationExit=%d (%d mins)",
      m_use_friday_exit, friday_time, m_friday_exit_mins, m_use_duration_exit, m_max_holding_mins));
}

//+------------------------------------------------------------------+
//| CloseAllPositions                                                |
//+------------------------------------------------------------------+
void CTradeManager::CloseAllPositions(const string symbol)
{
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == symbol && 
            PositionGetInteger(POSITION_MAGIC) == m_magic_number)
         {
            Logger.Warning(StringFormat("EMERGENCY EXIT: Closing position ticket %lld", (long)ticket));
            SetupFillingMode(symbol);
            if(m_trade.PositionClose(ticket, m_slippage))
            {
               Logger.Trade(StringFormat("Emergency Close Success: Ticket %lld", (long)ticket));
            }
            else
            {
               Logger.Error(StringFormat("Emergency Close Failed: Ticket %lld. Error code: %d", (long)ticket, m_trade.ResultRetcode()));
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| ProcessTimeExits                                                 |
//+------------------------------------------------------------------+
void CTradeManager::ProcessTimeExits(const string symbol)
{
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   
   // 1. Friday Exit
   if(m_use_friday_exit && dt.day_of_week == 5) // Friday
   {
      int current_mins = (dt.hour * 60) + dt.min;
      if(current_mins >= m_friday_exit_mins)
      {
         Logger.Info("Friday time exit trigger. Closing all active positions.");
         CloseAllPositions(symbol);
         return;
      }
   }
   
   // 2. Maximum Holding Duration Exit
   if(m_use_duration_exit && m_max_holding_mins > 0)
   {
      int total = PositionsTotal();
      for(int i = total - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket > 0)
         {
            if(PositionGetString(POSITION_SYMBOL) == symbol && 
               PositionGetInteger(POSITION_MAGIC) == m_magic_number)
            {
               datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);
               long elapsed_sec = (long)now - (long)open_time;
               if(elapsed_sec >= m_max_holding_mins * 60)
                 {
                    Logger.Info(StringFormat("Trade Duration Exit: Position ticket %lld exceeded max holding time (%d mins)", (long)ticket, m_max_holding_mins));
                    SetupFillingMode(symbol);
                    if(m_trade.PositionClose(ticket, m_slippage))
                    {
                       Logger.Trade(StringFormat("Duration Close Success: Ticket %lld", (long)ticket));
                    }
                 }
            }
         }
      }
   }
}
