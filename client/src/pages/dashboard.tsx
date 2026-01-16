import { Layout } from "@/components/layout";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { EquityChart } from "@/components/equity-chart";
import { useTrades } from "@/hooks/use-trades";
import { useMT5Accounts } from "@/hooks/use-mt5-accounts";
import { ArrowUpRight, ArrowDownRight, TrendingUp, Activity, DollarSign, BarChart3, Sparkles, Loader2, Wallet } from "lucide-react";
import { cn } from "@/lib/utils";
import { useMemo } from "react";

export default function Dashboard() {
  const { data: trades = [], isLoading: isLoadingTrades } = useTrades();
  const { data: accounts = [], isLoading: isLoadingAccounts } = useMT5Accounts();

  const isLoading = isLoadingTrades || isLoadingAccounts;

  const stats = useMemo(() => {
    const totalInitialBalance = accounts.reduce((sum, acc) => sum + (acc.initial_balance || 0), 0);
    const totalPnl = trades.reduce((sum, t) => sum + t.net_pnl, 0);
    const currentBalance = totalInitialBalance + totalPnl;

    if (!trades.length) {
      return [
        { label: "Account Balance", value: `$${totalInitialBalance.toFixed(2)}`, subtext: "Starting balance", icon: Wallet, trend: "neutral" },
        { label: "Net Profit", value: "$0.00", subtext: "No trades yet", icon: DollarSign, trend: "neutral" },
        { label: "Win Rate", value: "0%", subtext: "No trades yet", icon: Activity, trend: "neutral" },
        { label: "Profit Factor", value: "0.0", subtext: "Gross Profit / Gross Loss", icon: TrendingUp, trend: "neutral" }
      ];
    }

    const wins = trades.filter(t => t.net_pnl > 0).length;
    const winRate = ((wins / trades.length) * 100).toFixed(0);
    
    const grossProfit = trades.filter(t => t.net_pnl > 0).reduce((sum, t) => sum + t.net_pnl, 0);
    const grossLoss = Math.abs(trades.filter(t => t.net_pnl < 0).reduce((sum, t) => sum + t.net_pnl, 0));
    const profitFactor = grossLoss > 0 ? (grossProfit / grossLoss).toFixed(1) : "∞";
    
    const avgR = trades
      .filter(t => t.risk && t.risk_cash)
      .reduce((sum, t) => sum + (t.net_pnl / (t.risk_cash || 1)), 0) / Math.max(1, trades.filter(t => t.risk).length);

    return [
      {
        label: "Account Balance",
        value: `$${currentBalance.toFixed(2)}`,
        subtext: `Equity: $${currentBalance.toFixed(2)}`,
        icon: Wallet,
        trend: totalPnl >= 0 ? "up" : "down"
      },
      {
        label: "Net Profit",
        value: totalPnl >= 0 ? `+$${totalPnl.toFixed(2)}` : `-$${Math.abs(totalPnl).toFixed(2)}`,
        subtext: `${trades.length} total trades`,
        icon: DollarSign,
        trend: totalPnl > 0 ? "up" : "down"
      },
      {
        label: "Win Rate",
        value: `${winRate}%`,
        subtext: `${wins} wins, ${trades.length - wins} losses`,
        icon: Activity,
        trend: "neutral"
      },
      {
        label: "Profit Factor",
        value: profitFactor,
        subtext: "Gross Profit / Gross Loss",
        icon: TrendingUp,
        trend: parseFloat(profitFactor) > 1 ? "up" : "down"
      }
    ];
  }, [trades, accounts]);

  if (isLoading) {
    return (
      <Layout>
        <div className="flex items-center justify-center h-screen">
          <Loader2 className="w-8 h-8 animate-spin text-primary" />
        </div>
      </Layout>
    );
  }

  return (
    <Layout>
      <div className="p-8 space-y-8 max-w-[1600px] mx-auto">
        <div className="flex flex-col gap-2">
          <h1 className="text-3xl font-bold tracking-tight">Dashboard</h1>
          <p className="text-muted-foreground">Welcome back, John. Here's your trading performance overview.</p>
        </div>

        {/* Top Stats Grid */}
        <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
          {stats.map((stat, i) => (
            <Card key={i} className="bg-card border-border shadow-sm hover:border-primary/50 transition-colors">
              <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                <CardTitle className="text-sm font-medium text-muted-foreground uppercase tracking-wider">
                  {stat.label}
                </CardTitle>
                <stat.icon className="h-4 w-4 text-muted-foreground" />
              </CardHeader>
              <CardContent>
                <div className="text-2xl font-bold font-mono tracking-tight">{stat.value}</div>
                <p className="text-xs text-muted-foreground mt-1">{stat.subtext}</p>
              </CardContent>
            </Card>
          ))}
        </div>

        {/* Main Chart Section */}
        <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4 h-[400px]">
          <EquityChart />
          
          <Card className="col-span-4 lg:col-span-1 h-full flex flex-col">
            <CardHeader>
              <CardTitle className="text-sm font-medium text-muted-foreground uppercase tracking-wider">Recent Activity</CardTitle>
            </CardHeader>
            <CardContent className="flex-1 overflow-auto pr-2">
              <div className="space-y-4">
                {trades.length === 0 ? (
                  <div className="text-sm text-muted-foreground text-center py-8">
                    No trades yet. Start by adding your first trade!
                  </div>
                ) : (
                  trades.slice(0, 5).map(trade => (
                    <div key={trade.id} className="flex items-center justify-between text-sm group cursor-pointer hover:bg-accent/50 p-2 rounded-md -mx-2 transition-colors">
                      <div className="flex items-center gap-3">
                        <div className={cn(
                          "w-2 h-2 rounded-full",
                          trade.net_pnl > 0 ? "bg-profit" : "bg-loss"
                        )} />
                        <div className="flex flex-col">
                          <span className="font-bold font-mono">{trade.symbol}</span>
                          <span className="text-xs text-muted-foreground capitalize">{trade.side.toLowerCase()} • {trade.volume} lot</span>
                        </div>
                      </div>
                      <div className={cn(
                        "font-mono font-medium",
                        trade.net_pnl > 0 ? "text-profit" : "text-loss"
                      )}>
                        {trade.net_pnl > 0 ? "+" : ""}{trade.net_pnl.toFixed(0)}
                      </div>
                    </div>
                  ))
                )}
              </div>
            </CardContent>
          </Card>
        </div>

        {/* AI Insight Section */}
        <Card className="bg-gradient-to-br from-sidebar to-card border-border">
          <CardHeader>
            <div className="flex items-center gap-2">
              <Sparkles className="w-5 h-5 text-primary" />
              <CardTitle>Weekly AI Insight</CardTitle>
            </div>
          </CardHeader>
          <CardContent>
            <div className="grid md:grid-cols-3 gap-6">
              <div className="space-y-2">
                <h4 className="text-sm font-semibold text-muted-foreground uppercase tracking-wider">Top Strength</h4>
                <p className="text-sm">You are executing trend continuations on <span className="text-foreground font-mono font-bold">EURUSD</span> with high accuracy (85%).</p>
              </div>
              <div className="space-y-2">
                <h4 className="text-sm font-semibold text-muted-foreground uppercase tracking-wider">Main Leak</h4>
                <p className="text-sm">Counter-trend trades during the Asian session are accounting for <span className="text-destructive font-bold">60%</span> of your losses.</p>
              </div>
              <div className="space-y-2">
                <h4 className="text-sm font-semibold text-muted-foreground uppercase tracking-wider">Action Item</h4>
                <p className="text-sm">Consider filtering out reversal setups between 22:00 - 06:00 UTC.</p>
              </div>
            </div>
          </CardContent>
        </Card>
      </div>
    </Layout>
  );
}
