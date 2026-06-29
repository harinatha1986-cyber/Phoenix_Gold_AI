//+------------------------------------------------------------------+
//|                                                    Dashboard.mqh |
//|                                  Copyright 2026, Phoenix Gold AI |
//|                                       https://www.google.com/    |
//|                                                                  |
//| Implements a beautiful, premium visual HUD overlay on the chart, |
//| rendering real-time metrics, risk statistics, and market states. |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Phoenix Gold AI"
#property link      "https://www.google.com/"
#property version   "1.00"
#property once

#include "Utilities.mqh"
#include "Logger.mqh"

//+------------------------------------------------------------------+
//| Class CDashboard                                                 |
//| Handles drawing and refreshing visual stats on the chart        |
//+------------------------------------------------------------------+
class CDashboard
{
private:
   long     m_chart_id;
   int      m_sub_window;
   string   m_prefix;
   
   // Panel Coordinates
   int      m_pos_x;
   int      m_pos_y;
   int      m_width;
   int      m_height;
   
   // Color Palette
   color    m_color_bg;
   color    m_color_border;
   color    m_color_gold;
   color    m_color_text;
   color    m_color_green;
   color    m_color_red;
   color    m_color_gray;

   // Drawing Helpers
   void     CreatePanel(const string name, const int x, const int y, const int w, const int h);
   void     CreateLabel(const string name, const string text, const int x, const int y, 
                        const color clr, const int font_size, const int anchor=ANCHOR_LEFT);
   void     UpdateLabelText(const string name, const string text, const color clr);

public:
            CDashboard();
           ~CDashboard();
           
   // Initialize Dashboard HUD
   void     Init(const int x=20, const int y=50);
   
   // Refresh data values
   void     Update(const double balance, const double equity, const double profit, const double drawdown,
                   const string trend, const double ema20, const double ema50, const double ema200,
                   const double atr, const double rsi, const double spread, const int open_trades,
                   const int day_trades, const double win_rate, const string status);
                   
   // Delete all graphical objects
   void     Destroy();
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CDashboard::CDashboard() : m_chart_id(0),
                           m_sub_window(0),
                           m_prefix("PGAI_HUD_"),
                           m_pos_x(20),
                           m_pos_y(50),
                           m_width(620),
                           m_height(240)
{
   // Sleek HSL/Dark Mode Colors
   m_color_bg     = C'22,25,30';         // Dark Navy Gray
   m_color_border = C'45,52,64';         // Muted Blue-Gray
   m_color_gold   = C'255,200,60';       // Rich Gold Accent
   m_color_text   = C'230,235,245';      // Bright Cool Silver/White
   m_color_green  = C'50,220,120';       // Emerald Green
   m_color_red    = C'255,80,90';        // Vibrant Alert Crimson
   m_color_gray   = C'140,150,165';      // Secondary Muted Label
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CDashboard::~CDashboard()
{
   Destroy();
}

//+------------------------------------------------------------------+
//| CreatePanel                                                      |
//+------------------------------------------------------------------+
void CDashboard::CreatePanel(const string name, const int x, const int y, const int w, const int h)
{
   string obj_name = m_prefix + name;
   ObjectDelete(m_chart_id, obj_name);
   
   if(ObjectCreate(m_chart_id, obj_name, OBJ_RECTANGLE_LABEL, m_sub_window, 0, 0))
   {
      ObjectSetInteger(m_chart_id, obj_name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(m_chart_id, obj_name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(m_chart_id, obj_name, OBJPROP_XSIZE, w);
      ObjectSetInteger(m_chart_id, obj_name, OBJPROP_YSIZE, h);
      ObjectSetInteger(m_chart_id, obj_name, OBJPROP_BGCOLOR, m_color_bg);
      ObjectSetInteger(m_chart_id, obj_name, OBJPROP_BORDER_COLOR, m_color_border);
      ObjectSetInteger(m_chart_id, obj_name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(m_chart_id, obj_name, OBJPROP_BACK, false);
      ObjectSetInteger(m_chart_id, obj_name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(m_chart_id, obj_name, OBJPROP_SELECTED, false);
      ObjectSetInteger(m_chart_id, obj_name, OBJPROP_HIDDEN, true);
   }
}

//+------------------------------------------------------------------+
//| CreateLabel                                                      |
//+------------------------------------------------------------------+
void CDashboard::CreateLabel(const string name, const string text, const int x, const int y, 
                             const color clr, const int font_size, const int anchor=ANCHOR_LEFT)
{
   string obj_name = m_prefix + name;
   ObjectDelete(m_chart_id, obj_name);
   
   if(ObjectCreate(m_chart_id, obj_name, OBJ_LABEL, m_sub_window, 0, 0))
   {
      ObjectSetInteger(m_chart_id, obj_name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(m_chart_id, obj_name, OBJPROP_YDISTANCE, y);
      ObjectSetString(m_chart_id, obj_name, OBJPROP_TEXT, text);
      ObjectSetString(m_chart_id, obj_name, OBJPROP_FONT, "Segoe UI");
      ObjectSetInteger(m_chart_id, obj_name, OBJPROP_FONTSIZE, font_size);
      ObjectSetInteger(m_chart_id, obj_name, OBJPROP_COLOR, clr);
      ObjectSetInteger(m_chart_id, obj_name, OBJPROP_ANCHOR, anchor);
      ObjectSetInteger(m_chart_id, obj_name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(m_chart_id, obj_name, OBJPROP_SELECTED, false);
      ObjectSetInteger(m_chart_id, obj_name, OBJPROP_HIDDEN, true);
   }
}

//+------------------------------------------------------------------+
//| UpdateLabelText                                                  |
//+------------------------------------------------------------------+
void CDashboard::UpdateLabelText(const string name, const string text, const color clr)
{
   string obj_name = m_prefix + name;
   ObjectSetString(m_chart_id, obj_name, OBJPROP_TEXT, text);
   ObjectSetInteger(m_chart_id, obj_name, OBJPROP_COLOR, clr);
}

//+------------------------------------------------------------------+
//| Init                                                             |
//+------------------------------------------------------------------+
void CDashboard::Init(const int x=20, const int y=50)
{
   m_pos_x = x;
   m_pos_y = y;
   m_chart_id = ChartID();
   
   // Clean any leftover visual objects
   Destroy();
   
   // 1. Draw Main Dashboard Container Panel
   CreatePanel("BG", m_pos_x, m_pos_y, m_width, m_height);
   
   // 2. Draw HUD Header Title
   CreateLabel("Header", "PHOENIX GOLD AI  v1.00", m_pos_x + 15, m_pos_y + 12, m_color_gold, 11);
   CreateLabel("Time", TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES), m_pos_x + m_width - 15, m_pos_y + 12, m_color_gray, 9, ANCHOR_RIGHT);
   
   // Draw horizontal divider
   CreatePanel("Divider", m_pos_x + 15, m_pos_y + 35, m_width - 30, 2);
   ObjectSetInteger(m_chart_id, m_prefix + "Divider", OBJPROP_BGCOLOR, m_color_border);
   ObjectSetInteger(m_chart_id, m_prefix + "Divider", OBJPROP_BORDER_COLOR, m_color_border);

   // 3. Grid Columns (Initialize Static Text Labels)
   int col1_x = m_pos_x + 20;
   int col2_x = m_pos_x + 220;
   int col3_x = m_pos_x + 420;
   
   int line1_y = m_pos_y + 50;
   int line2_y = m_pos_y + 80;
   int line3_y = m_pos_y + 110;
   int line4_y = m_pos_y + 140;
   int line5_y = m_pos_y + 170;
   int line6_y = m_pos_y + 200;

   // --- COLUMN 1: ACCOUNT METRICS ---
   CreateLabel("L_Balance",  "Balance:", col1_x, line1_y, m_color_gray, 9);
   CreateLabel("V_Balance",  "$0.00", col1_x + 140, line1_y, m_color_text, 9, ANCHOR_RIGHT);
   
   CreateLabel("L_Equity",   "Equity:", col1_x, line2_y, m_color_gray, 9);
   CreateLabel("V_Equity",   "$0.00", col1_x + 140, line2_y, m_color_text, 9, ANCHOR_RIGHT);
   
   CreateLabel("L_Profit",   "Profit (Day):", col1_x, line3_y, m_color_gray, 9);
   CreateLabel("V_Profit",   "$0.00", col1_x + 140, line3_y, m_color_green, 9, ANCHOR_RIGHT);
   
   CreateLabel("L_Drawdown", "Drawdown:", col1_x, line4_y, m_color_gray, 9);
   CreateLabel("V_Drawdown", "0.00%", col1_x + 140, line4_y, m_color_text, 9, ANCHOR_RIGHT);

   // --- COLUMN 2: MARKET ANALYSIS ---
   CreateLabel("L_Trend",    "Trend (H1):", col2_x, line1_y, m_color_gray, 9);
   CreateLabel("V_Trend",    "NEUTRAL", col2_x + 150, line1_y, m_color_text, 9, ANCHOR_RIGHT);
   
   CreateLabel("L_EMA",      "EMAs (20/50/200):", col2_x, line2_y, m_color_gray, 9);
   CreateLabel("V_EMA",      "0.0 / 0.0 / 0.0", col2_x + 150, line2_y, m_color_text, 8, ANCHOR_RIGHT);
   
   CreateLabel("L_ATR",      "ATR (14):", col2_x, line3_y, m_color_gray, 9);
   CreateLabel("V_ATR",      "0.00 points", col2_x + 150, line3_y, m_color_text, 9, ANCHOR_RIGHT);
   
   CreateLabel("L_RSI",      "RSI (14):", col2_x, line4_y, m_color_gray, 9);
   CreateLabel("V_RSI",      "50.0", col2_x + 150, line4_y, m_color_text, 9, ANCHOR_RIGHT);

   // --- COLUMN 3: EA STATISTICS ---
   CreateLabel("L_Spread",   "Spread:", col3_x, line1_y, m_color_gray, 9);
   CreateLabel("V_Spread",   "0.0 pts", col3_x + 160, line1_y, m_color_text, 9, ANCHOR_RIGHT);
   
   CreateLabel("L_Trades",   "Open Trades:", col3_x, line2_y, m_color_gray, 9);
   CreateLabel("V_Trades",   "0", col3_x + 160, line2_y, m_color_text, 9, ANCHOR_RIGHT);
   
   CreateLabel("L_DayTrds",  "Daily Trades:", col3_x, line3_y, m_color_gray, 9);
   CreateLabel("V_DayTrds",  "0", col3_x + 160, line3_y, m_color_text, 9, ANCHOR_RIGHT);
   
   CreateLabel("L_WinRate",  "Win Rate (Day):", col3_x, line4_y, m_color_gray, 9);
   CreateLabel("V_WinRate",  "0.0%", col3_x + 160, line4_y, m_color_text, 9, ANCHOR_RIGHT);
   
   CreateLabel("L_Status",   "Status:", col3_x, line5_y, m_color_gray, 9);
   CreateLabel("V_Status",   "SCANNING", col3_x + 160, line5_y, m_color_green, 9, ANCHOR_RIGHT);
   
   // --- FOOTER INFORMATION ---
   CreateLabel("FooterText", "XAUUSD M15 • Pure SMC & Technical Confluence Engine", m_pos_x + 15, line6_y, m_color_gray, 8);
   
   ChartRedraw(m_chart_id);
}

//+------------------------------------------------------------------+
//| Update                                                           |
//+------------------------------------------------------------------+
void CDashboard::Update(const double balance, const double equity, const double profit, const double drawdown,
                        const string trend, const double ema20, const double ema50, const double ema200,
                        const double atr, const double rsi, const double spread, const int open_trades,
                        const int day_trades, const double win_rate, const string status)
{
   // Reconstructed formats
   string bal_str = "$" + CUtilities::FormatMoney(balance, 2);
   string eq_str  = "$" + CUtilities::FormatMoney(equity, 2);
   
   color prof_color = (profit >= 0.0) ? m_color_green : m_color_red;
   string prof_str  = (profit >= 0.0) ? "+" : "";
   prof_str += "$" + CUtilities::FormatMoney(profit, 2);
   
   color dd_color = (drawdown >= 5.0) ? m_color_red : (drawdown > 0.0) ? m_color_gold : m_color_text;
   string dd_str  = DoubleToString(drawdown, 2) + "%";
   
   color trend_color = (trend == "UPTREND") ? m_color_green : (trend == "DOWNTREND") ? m_color_red : m_color_text;
   
   string ema_str = StringFormat("%.1f/%.1f/%.1f", ema20, ema50, ema200);
   string atr_str = DoubleToString(atr, 2) + " pts";
   string rsi_str = DoubleToString(rsi, 2);
   string spread_str = DoubleToString(spread, 1) + " pts";
   
   color status_color = (status == "SCANNING") ? m_color_green : 
                        (status == "PAUSED (NEWS)" || status == "PAUSED (SESSION)" || status == "PAUSED (WEEKEND)") ? m_color_gold : m_color_red;
   
   // Update Label Values
   UpdateLabelText("Time", TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES), m_color_gray);
   UpdateLabelText("V_Balance", bal_str, m_color_text);
   UpdateLabelText("V_Equity", eq_str, m_color_text);
   UpdateLabelText("V_Profit", prof_str, prof_color);
   UpdateLabelText("V_Drawdown", dd_str, dd_color);
   UpdateLabelText("V_Trend", trend, trend_color);
   UpdateLabelText("V_EMA", ema_str, m_color_text);
   UpdateLabelText("V_ATR", atr_str, m_color_text);
   UpdateLabelText("V_RSI", rsi_str, m_color_text);
   UpdateLabelText("V_Spread", spread_str, m_color_text);
   UpdateLabelText("V_Trades", (string)open_trades, m_color_text);
   UpdateLabelText("V_DayTrds", (string)day_trades, m_color_text);
   UpdateLabelText("V_WinRate", DoubleToString(win_rate, 1) + "%", m_color_text);
   UpdateLabelText("V_Status", status, status_color);
   
   ChartRedraw(m_chart_id);
}

//+------------------------------------------------------------------+
//| Destroy                                                          |
//+------------------------------------------------------------------+
void CDashboard::Destroy()
{
   // Query chart ID in case it was destructed on shut down
   long cid = (m_chart_id > 0) ? m_chart_id : ChartID();
   
   // Delete all objects starting with prefix
   int total = ObjectsTotal(cid, m_sub_window, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(cid, i, m_sub_window, -1);
      if(StringFind(name, m_prefix) == 0)
      {
         ObjectDelete(cid, name);
      }
   }
   ChartRedraw(cid);
}
