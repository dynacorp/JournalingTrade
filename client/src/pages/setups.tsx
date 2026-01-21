import { useState } from "react";
import { Layout } from "@/components/layout";
import { SetupQueue } from "@/components/setups/setup-queue";
import { SetupDetail } from "@/components/setups/setup-detail";
import { useChartSnapshots, useChartSnapshotStats, useDeleteAllSnapshots, type ChartSnapshotListItem } from "@/hooks/use-chart-snapshots";
import type { ChartSnapshotStatus } from "@shared/schema";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Loader2, Target, Clock, CheckCircle, AlertCircle, Trash2 } from "lucide-react";
import { useToast } from "@/hooks/use-toast";

type FilterStatus = ChartSnapshotStatus | "all";

export default function Setups() {
  const [selectedSnapshot, setSelectedSnapshot] = useState<ChartSnapshotListItem | null>(null);
  const [statusFilter, setStatusFilter] = useState<FilterStatus>("all");
  const [symbolFilter, setSymbolFilter] = useState<string>("all");
  const [timeframeFilter, setTimeframeFilter] = useState<string>("all");

  const { toast } = useToast();
  const { data: stats, isLoading: statsLoading } = useChartSnapshotStats();
  const { data: snapshots = [], isLoading } = useChartSnapshots(
    statusFilter === "all" ? undefined : { status: statusFilter as ChartSnapshotStatus }
  );
  const deleteAllMutation = useDeleteAllSnapshots();

  // Get unique symbols and timeframes for filters
  const symbols = Array.from(new Set(snapshots.map(s => s.symbol))).sort();
  const timeframes = Array.from(new Set(snapshots.map(s => s.timeframe))).sort();

  // Apply local filters
  const filteredSnapshots = snapshots.filter(s => {
    if (symbolFilter !== "all" && s.symbol !== symbolFilter) return false;
    if (timeframeFilter !== "all" && s.timeframe !== timeframeFilter) return false;
    return true;
  });

  const handleClearAll = async () => {
    const filters: { status?: string; symbol?: string; timeframe?: string } = {};
    if (statusFilter !== "all") filters.status = statusFilter;
    if (symbolFilter !== "all") filters.symbol = symbolFilter;
    if (timeframeFilter !== "all") filters.timeframe = timeframeFilter;

    const hasFilters = Object.keys(filters).length > 0;
    const confirmMessage = hasFilters
      ? `Are you sure you want to delete all ${filteredSnapshots.length} filtered snapshots? This cannot be undone.`
      : `Are you sure you want to delete ALL ${snapshots.length} snapshots? This cannot be undone.`;

    if (!confirm(confirmMessage)) return;

    try {
      const result = await deleteAllMutation.mutateAsync(hasFilters ? filters : undefined);
      toast({
        title: "Deleted",
        description: `Successfully deleted ${result.deleted_count} snapshot(s).`,
      });
      setSelectedSnapshot(null);
    } catch {
      toast({
        title: "Error",
        description: "Failed to delete snapshots.",
        variant: "destructive",
      });
    }
  };

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
      <div className="p-8 space-y-6 max-w-[1600px] mx-auto">
        {/* Header */}
        <div className="flex flex-col md:flex-row items-start md:items-center justify-between gap-4">
          <div>
            <h1 className="text-3xl font-bold tracking-tight">Chart Setups</h1>
            <p className="text-muted-foreground">Review and analyze chart screenshots from MT5.</p>
          </div>
          {snapshots.length > 0 && (
            <Button
              variant="destructive"
              size="sm"
              onClick={handleClearAll}
              disabled={deleteAllMutation.isPending}
            >
              {deleteAllMutation.isPending ? (
                <Loader2 className="w-4 h-4 mr-2 animate-spin" />
              ) : (
                <Trash2 className="w-4 h-4 mr-2" />
              )}
              {statusFilter !== "all" || symbolFilter !== "all" || timeframeFilter !== "all"
                ? `Clear Filtered (${filteredSnapshots.length})`
                : `Clear All (${snapshots.length})`}
            </Button>
          )}
        </div>

        {/* Stats Cards */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <Card>
            <CardContent className="pt-4 pb-4">
              <div className="flex items-center gap-3">
                <div className="p-2 rounded-lg bg-yellow-500/10">
                  <Clock className="w-5 h-5 text-yellow-500" />
                </div>
                <div>
                  <p className="text-2xl font-bold">{stats?.pending ?? 0}</p>
                  <p className="text-xs text-muted-foreground">Pending</p>
                </div>
              </div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="pt-4 pb-4">
              <div className="flex items-center gap-3">
                <div className="p-2 rounded-lg bg-blue-500/10">
                  <AlertCircle className="w-5 h-5 text-blue-500" />
                </div>
                <div>
                  <p className="text-2xl font-bold">{stats?.queued ?? 0}</p>
                  <p className="text-xs text-muted-foreground">In Review</p>
                </div>
              </div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="pt-4 pb-4">
              <div className="flex items-center gap-3">
                <div className="p-2 rounded-lg bg-emerald-500/10">
                  <CheckCircle className="w-5 h-5 text-emerald-500" />
                </div>
                <div>
                  <p className="text-2xl font-bold">{stats?.analyzed ?? 0}</p>
                  <p className="text-xs text-muted-foreground">Analyzed</p>
                </div>
              </div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="pt-4 pb-4">
              <div className="flex items-center gap-3">
                <div className="p-2 rounded-lg bg-primary/10">
                  <Target className="w-5 h-5 text-primary" />
                </div>
                <div>
                  <p className="text-2xl font-bold">{stats?.high_score_count ?? 0}</p>
                  <p className="text-xs text-muted-foreground">High Score</p>
                </div>
              </div>
            </CardContent>
          </Card>
        </div>

        {/* Filters */}
        <div className="flex flex-col md:flex-row gap-4 items-start md:items-center">
          <Tabs value={statusFilter} onValueChange={(v) => setStatusFilter(v as FilterStatus)} className="w-full md:w-auto">
            <TabsList>
              <TabsTrigger value="all">All</TabsTrigger>
              <TabsTrigger value="queued_for_review">
                Review
                {stats?.queued ? <Badge variant="secondary" className="ml-1.5 px-1.5 py-0 text-[10px]">{stats.queued}</Badge> : null}
              </TabsTrigger>
              <TabsTrigger value="analyzed">Analyzed</TabsTrigger>
              <TabsTrigger value="no_setup">No Setup</TabsTrigger>
              <TabsTrigger value="discarded">Discarded</TabsTrigger>
            </TabsList>
          </Tabs>

          <div className="flex gap-2">
            <Select value={symbolFilter} onValueChange={setSymbolFilter}>
              <SelectTrigger className="w-[120px]">
                <SelectValue placeholder="Symbol" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All Symbols</SelectItem>
                {symbols.map(s => (
                  <SelectItem key={s} value={s}>{s}</SelectItem>
                ))}
              </SelectContent>
            </Select>

            <Select value={timeframeFilter} onValueChange={setTimeframeFilter}>
              <SelectTrigger className="w-[100px]">
                <SelectValue placeholder="Timeframe" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All TFs</SelectItem>
                {timeframes.map(tf => (
                  <SelectItem key={tf} value={tf}>{tf}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
        </div>

        {/* Main Content */}
        {filteredSnapshots.length === 0 ? (
          <Card>
            <CardContent className="py-16 text-center">
              <Target className="w-12 h-12 mx-auto mb-4 text-muted-foreground/50" />
              <h3 className="text-lg font-semibold mb-2">No Chart Snapshots</h3>
              <p className="text-muted-foreground max-w-md mx-auto">
                {statusFilter === "all"
                  ? "Chart snapshots from your MT5 Expert Advisor will appear here. Configure your EA to send screenshots for analysis."
                  : `No snapshots with status "${statusFilter.replace(/_/g, " ")}".`}
              </p>
            </CardContent>
          </Card>
        ) : (
          <SetupQueue
            snapshots={filteredSnapshots}
            onSelectSnapshot={setSelectedSnapshot}
            selectedId={selectedSnapshot?.id}
          />
        )}

        {/* Detail Sheet */}
        <SetupDetail
          snapshotId={selectedSnapshot?.id ?? null}
          isOpen={!!selectedSnapshot}
          onClose={() => setSelectedSnapshot(null)}
        />
      </div>
    </Layout>
  );
}
