import { useState } from "react";
import { format } from "date-fns";
import { cn } from "@/lib/utils";
import {
  useChartSnapshot,
  useChartSnapshotGroup,
  useApproveSnapshot,
  useDiscardSnapshot,
  useAnalyzeSnapshot,
  useAnalyzeGroup,
  useUpdateSnapshotNotes,
  useMarkJournalCandidate,
  useDeleteSnapshot,
  useGenerateAnnotations,
  type GroupedChartSnapshot,
  type ChartAnnotation,
} from "@/hooks/use-chart-snapshots";
import { Sheet, SheetContent, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Textarea } from "@/components/ui/textarea";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Progress } from "@/components/ui/progress";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Separator } from "@/components/ui/separator";
import {
  Loader2,
  CheckCircle,
  XCircle,
  RefreshCw,
  BookMarked,
  Link2,
  TrendingUp,
  TrendingDown,
  Target,
  AlertTriangle,
  Layers,
  Activity,
  BarChart3,
  Zap,
  Clock,
  ArrowUp,
  ArrowDown,
  Trash2,
  Eye,
} from "lucide-react";
import { useToast } from "@/hooks/use-toast";
import { VisualAnnotations } from "@/components/chart-annotations";

interface SetupDetailProps {
  snapshotId: number | null;
  isOpen: boolean;
  onClose: () => void;
}

const confluenceLabels = {
  market_structure_score: { label: "Market Structure", icon: Layers, weight: 25 },
  key_levels_score: { label: "Key Levels", icon: Target, weight: 20 },
  liquidity_score: { label: "Liquidity", icon: Activity, weight: 15 },
  impulse_origin_score: { label: "Impulse & Origin", icon: Zap, weight: 15 },
  imbalance_score: { label: "Imbalance", icon: BarChart3, weight: 15 },
  candle_action_score: { label: "Candle Action", icon: AlertTriangle, weight: 10 },
};

// Helper component for group snapshot cards
function GroupSnapshotCard({
  snapshot,
  isSelected,
  onSelect,
}: {
  snapshot: GroupedChartSnapshot;
  isSelected: boolean;
  onSelect: () => void;
}) {
  const score = snapshot.confluence_score ?? snapshot.pre_analysis_score ?? 0;
  const isAnalyzed = !!snapshot.full_analysis_parsed;
  const BiasIcon = snapshot.pre_analysis_bias === "bullish" ? TrendingUp
    : snapshot.pre_analysis_bias === "bearish" ? TrendingDown
    : null;

  return (
    <div
      onClick={onSelect}
      className={cn(
        "p-3 rounded-lg border cursor-pointer transition-all",
        isSelected
          ? "border-primary bg-primary/5"
          : "border-border hover:border-primary/50 bg-muted/30"
      )}
    >
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <Badge variant="outline" className="font-mono font-bold">
            {snapshot.timeframe}
          </Badge>
          {isAnalyzed ? (
            <CheckCircle className="w-4 h-4 text-emerald-500" />
          ) : (
            <Clock className="w-4 h-4 text-muted-foreground" />
          )}
        </div>
        <div className="flex items-center gap-2">
          {BiasIcon && (
            <BiasIcon
              className={cn(
                "w-4 h-4",
                snapshot.pre_analysis_bias === "bullish" ? "text-emerald-500" : "text-red-500"
              )}
            />
          )}
          <span
            className={cn(
              "font-bold",
              score >= 70 ? "text-emerald-500" :
              score >= 50 ? "text-yellow-500" : "text-muted-foreground"
            )}
          >
            {score.toFixed(0)}
          </span>
        </div>
      </div>
      {snapshot.pre_analysis_summary && (
        <p className="text-xs text-muted-foreground mt-2 line-clamp-1">
          {snapshot.pre_analysis_summary}
        </p>
      )}
    </div>
  );
}

export function SetupDetail({ snapshotId, isOpen, onClose }: SetupDetailProps) {
  const { toast } = useToast();
  const [notes, setNotes] = useState("");
  const [activeTab, setActiveTab] = useState("overview");
  const [selectedGroupTf, setSelectedGroupTf] = useState<string | null>(null);
  const [annotations, setAnnotations] = useState<ChartAnnotation[]>([]);

  const { data: snapshot, isLoading } = useChartSnapshot(snapshotId);
  const { data: groupSnapshots } = useChartSnapshotGroup(snapshot?.group_id ?? null);
  const approveMutation = useApproveSnapshot();
  const discardMutation = useDiscardSnapshot();
  const analyzeMutation = useAnalyzeSnapshot();
  const analyzeGroupMutation = useAnalyzeGroup();
  const updateNotesMutation = useUpdateSnapshotNotes();
  const markJournalMutation = useMarkJournalCandidate();
  const deleteMutation = useDeleteSnapshot();
  const generateAnnotationsMutation = useGenerateAnnotations();

  const isActionLoading =
    approveMutation.isPending ||
    discardMutation.isPending ||
    analyzeMutation.isPending ||
    analyzeGroupMutation.isPending ||
    deleteMutation.isPending ||
    generateAnnotationsMutation.isPending;

  // Get HTF and LTF snapshots from group
  const htfSnapshots = groupSnapshots?.filter(s => s.tf_type === "htf") ?? [];
  const ltfSnapshots = groupSnapshots?.filter(s => s.tf_type === "ltf") ?? [];
  const hasGroup = groupSnapshots && groupSnapshots.length > 1;

  // Get the currently viewed group snapshot
  const viewedGroupSnapshot = selectedGroupTf
    ? groupSnapshots?.find(s => s.timeframe === selectedGroupTf)
    : null;

  const handleApprove = async () => {
    if (!snapshotId) return;
    try {
      await approveMutation.mutateAsync(snapshotId);
      toast({ title: "Analysis Started", description: "Full confluence analysis is running." });
    } catch {
      toast({ title: "Error", description: "Failed to approve snapshot.", variant: "destructive" });
    }
  };

  const handleDiscard = async () => {
    if (!snapshotId) return;
    try {
      await discardMutation.mutateAsync(snapshotId);
      toast({ title: "Discarded", description: "Snapshot has been discarded." });
      onClose();
    } catch {
      toast({ title: "Error", description: "Failed to discard snapshot.", variant: "destructive" });
    }
  };

  const handleReanalyze = async () => {
    if (!snapshotId) return;
    try {
      await analyzeMutation.mutateAsync(snapshotId);
      toast({ title: "Re-analysis Complete", description: "Confluence analysis has been updated." });
    } catch {
      toast({ title: "Error", description: "Failed to re-analyze snapshot.", variant: "destructive" });
    }
  };

  const handleSaveNotes = async () => {
    if (!snapshotId) return;
    try {
      await updateNotesMutation.mutateAsync({ id: snapshotId, notes });
      toast({ title: "Saved", description: "Notes have been saved." });
    } catch {
      toast({ title: "Error", description: "Failed to save notes.", variant: "destructive" });
    }
  };

  const handleToggleJournal = async () => {
    if (!snapshotId || !snapshot) return;
    try {
      await markJournalMutation.mutateAsync({
        id: snapshotId,
        isCandidate: !snapshot.is_journal_candidate,
      });
      toast({
        title: snapshot.is_journal_candidate ? "Removed from Journal" : "Added to Journal",
        description: snapshot.is_journal_candidate
          ? "This setup is no longer a journal candidate."
          : "This setup is now a journal candidate.",
      });
    } catch {
      toast({ title: "Error", description: "Failed to update journal status.", variant: "destructive" });
    }
  };

  const handleAnalyzeGroup = async () => {
    if (!snapshot?.group_id) return;
    try {
      await analyzeGroupMutation.mutateAsync(snapshot.group_id);
      toast({
        title: "Group Analysis Complete",
        description: "All timeframes in the group have been analyzed.",
      });
    } catch {
      toast({ title: "Error", description: "Failed to analyze group.", variant: "destructive" });
    }
  };

  const handleDelete = async () => {
    if (!snapshotId) return;
    if (!confirm("Are you sure you want to permanently delete this setup?")) return;
    try {
      await deleteMutation.mutateAsync(snapshotId);
      toast({ title: "Deleted", description: "Setup has been permanently deleted." });
      onClose();
    } catch {
      toast({ title: "Error", description: "Failed to delete setup.", variant: "destructive" });
    }
  };

  const handleGenerateAnnotations = async () => {
    if (!snapshotId) return;
    try {
      const result = await generateAnnotationsMutation.mutateAsync(snapshotId);
      setAnnotations(result.annotations);
      toast({
        title: "Breakdown Generated",
        description: `${result.annotations.length} annotations added to chart.`,
      });
    } catch {
      toast({ title: "Error", description: "Failed to generate chart breakdown.", variant: "destructive" });
    }
  };

  // Update notes state when snapshot loads
  if (snapshot && notes !== (snapshot.user_notes || "") && !updateNotesMutation.isPending) {
    setNotes(snapshot.user_notes || "");
  }

  const analysis = snapshot?.full_analysis_parsed;
  const canApprove = snapshot?.status === "queued_for_review" || snapshot?.status === "pre_analyzed";
  const canReanalyze = snapshot?.status === "analyzed" || snapshot?.status === "no_setup";
  const isAnalyzed = !!analysis;

  return (
    <Sheet open={isOpen} onOpenChange={(open) => !open && onClose()}>
      <SheetContent className="w-full sm:max-w-2xl overflow-hidden flex flex-col">
        <SheetHeader className="shrink-0">
          <SheetTitle className="flex items-center gap-2">
            {snapshot ? (
              <>
                <Badge variant="outline" className="font-mono font-bold">
                  {snapshot.symbol}
                </Badge>
                <Badge variant="secondary">{snapshot.timeframe}</Badge>
                <span className="text-muted-foreground text-sm font-normal">
                  {format(new Date(snapshot.snapshot_time), "MMM d, yyyy HH:mm")}
                </span>
              </>
            ) : (
              "Loading..."
            )}
          </SheetTitle>
        </SheetHeader>

        {isLoading ? (
          <div className="flex-1 flex items-center justify-center">
            <Loader2 className="w-8 h-8 animate-spin text-primary" />
          </div>
        ) : snapshot ? (
          <div className="flex-1 overflow-hidden flex flex-col">
            {/* Action Buttons */}
            <div className="flex flex-wrap gap-2 py-4 shrink-0">
              {hasGroup ? (
                <Button onClick={handleAnalyzeGroup} disabled={isActionLoading} size="sm">
                  {analyzeGroupMutation.isPending ? (
                    <Loader2 className="w-4 h-4 mr-2 animate-spin" />
                  ) : (
                    <Layers className="w-4 h-4 mr-2" />
                  )}
                  Analyze All Timeframes
                </Button>
              ) : canApprove ? (
                <Button onClick={handleApprove} disabled={isActionLoading} size="sm">
                  {approveMutation.isPending ? (
                    <Loader2 className="w-4 h-4 mr-2 animate-spin" />
                  ) : (
                    <CheckCircle className="w-4 h-4 mr-2" />
                  )}
                  Approve & Analyze
                </Button>
              ) : null}
              {canReanalyze && !hasGroup && (
                <Button onClick={handleReanalyze} disabled={isActionLoading} size="sm" variant="outline">
                  {analyzeMutation.isPending ? (
                    <Loader2 className="w-4 h-4 mr-2 animate-spin" />
                  ) : (
                    <RefreshCw className="w-4 h-4 mr-2" />
                  )}
                  Re-analyze
                </Button>
              )}
              <Button
                onClick={handleToggleJournal}
                disabled={markJournalMutation.isPending}
                size="sm"
                variant={snapshot.is_journal_candidate ? "default" : "outline"}
              >
                <BookMarked className="w-4 h-4 mr-2" />
                {snapshot.is_journal_candidate ? "In Journal" : "Add to Journal"}
              </Button>
              {snapshot.status !== "discarded" && (
                <Button onClick={handleDiscard} disabled={isActionLoading} size="sm" variant="ghost" className="text-destructive">
                  <XCircle className="w-4 h-4 mr-2" />
                  Discard
                </Button>
              )}
              <Button onClick={handleDelete} disabled={isActionLoading} size="sm" variant="ghost" className="text-destructive">
                {deleteMutation.isPending ? (
                  <Loader2 className="w-4 h-4 mr-2 animate-spin" />
                ) : (
                  <Trash2 className="w-4 h-4 mr-2" />
                )}
                Delete
              </Button>
            </div>

            <Tabs value={activeTab} onValueChange={setActiveTab} className="flex-1 flex flex-col overflow-hidden">
              <TabsList className="shrink-0 flex-wrap h-auto">
                <TabsTrigger value="overview">Overview</TabsTrigger>
                <TabsTrigger value="chart">Chart</TabsTrigger>
                {hasGroup && <TabsTrigger value="group">Group ({groupSnapshots?.length})</TabsTrigger>}
                {isAnalyzed && <TabsTrigger value="analysis">Analysis</TabsTrigger>}
                {snapshot.image_data && <TabsTrigger value="deep"><Eye className="w-3 h-3 mr-1" />Breakdown</TabsTrigger>}
                <TabsTrigger value="notes">Notes</TabsTrigger>
              </TabsList>

              <ScrollArea className="flex-1 mt-4">
                <TabsContent value="overview" className="m-0 space-y-4">
                  {/* Pre-Analysis Summary */}
                  <div className="space-y-2">
                    <h4 className="font-semibold text-sm">Pre-Analysis</h4>
                    <div className="p-3 bg-muted/50 rounded-lg">
                      <div className="flex items-center justify-between mb-2">
                        <span className="text-sm">Score</span>
                        <span className="font-bold">{snapshot.pre_analysis_score?.toFixed(0) ?? "—"}</span>
                      </div>
                      <p className="text-sm text-muted-foreground">{snapshot.pre_analysis_summary || "No summary available"}</p>
                      {snapshot.pre_analysis_bias && (
                        <div className="flex items-center gap-2 mt-2">
                          {snapshot.pre_analysis_bias === "bullish" ? (
                            <TrendingUp className="w-4 h-4 text-emerald-500" />
                          ) : snapshot.pre_analysis_bias === "bearish" ? (
                            <TrendingDown className="w-4 h-4 text-red-500" />
                          ) : null}
                          <span className="text-sm capitalize">{snapshot.pre_analysis_bias} bias</span>
                        </div>
                      )}
                    </div>
                  </div>

                  {/* Confluence Scores */}
                  {isAnalyzed && (
                    <div className="space-y-2">
                      <h4 className="font-semibold text-sm">Confluence Breakdown</h4>
                      <div className="space-y-3">
                        {Object.entries(confluenceLabels).map(([key, config]) => {
                          const score = snapshot[key as keyof typeof snapshot] as number | null;
                          const Icon = config.icon;
                          return (
                            <div key={key} className="space-y-1">
                              <div className="flex items-center justify-between text-sm">
                                <div className="flex items-center gap-2">
                                  <Icon className="w-4 h-4 text-muted-foreground" />
                                  <span>{config.label}</span>
                                  <span className="text-xs text-muted-foreground">({config.weight}%)</span>
                                </div>
                                <span className="font-mono">{score?.toFixed(0) ?? "—"}</span>
                              </div>
                              <Progress value={score ?? 0} className="h-1.5" />
                            </div>
                          );
                        })}
                      </div>
                      <Separator className="my-4" />
                      <div className="flex items-center justify-between">
                        <span className="font-semibold">Total Confluence Score</span>
                        <span
                          className={cn(
                            "text-2xl font-bold",
                            (snapshot.confluence_score ?? 0) >= 70 ? "text-emerald-500" :
                            (snapshot.confluence_score ?? 0) >= 50 ? "text-yellow-500" : "text-muted-foreground"
                          )}
                        >
                          {snapshot.confluence_score?.toFixed(0) ?? "—"}
                        </span>
                      </div>
                    </div>
                  )}

                  {/* Entry Logic */}
                  {isAnalyzed && analysis?.entry_logic && (
                    <div className="space-y-2">
                      <h4 className="font-semibold text-sm">Entry Logic</h4>
                      <div className="p-3 bg-muted/50 rounded-lg space-y-2">
                        <div className="flex items-center justify-between">
                          <span className="text-sm">Valid Setup</span>
                          <Badge variant={analysis.entry_logic.valid_setup ? "default" : "secondary"}>
                            {analysis.entry_logic.valid_setup ? "Yes" : "No"}
                          </Badge>
                        </div>
                        {analysis.entry_logic.valid_setup && (
                          <>
                            <div className="flex items-center justify-between">
                              <span className="text-sm">Direction</span>
                              <Badge variant={analysis.entry_logic.trade_direction === "long" ? "default" : "destructive"}>
                                {analysis.entry_logic.trade_direction?.toUpperCase()}
                              </Badge>
                            </div>
                            <div className="flex items-center justify-between">
                              <span className="text-sm">Entry Zone</span>
                              <span className="font-mono text-sm">{analysis.entry_logic.entry_zone}</span>
                            </div>
                            <div className="flex items-center justify-between">
                              <span className="text-sm">Invalidation</span>
                              <span className="font-mono text-sm">{analysis.entry_logic.invalidation_level}</span>
                            </div>
                            <div className="flex items-center justify-between">
                              <span className="text-sm">Confidence</span>
                              <span className="font-mono text-sm">{analysis.entry_logic.confidence}%</span>
                            </div>
                          </>
                        )}
                      </div>
                    </div>
                  )}

                  {/* Trade Link */}
                  {snapshot.linked_trade_id && (
                    <div className="p-3 bg-primary/5 border border-primary/20 rounded-lg">
                      <div className="flex items-center gap-2">
                        <Link2 className="w-4 h-4 text-primary" />
                        <span className="text-sm">
                          Linked to Trade #{snapshot.linked_trade_id}
                          {snapshot.auto_linked && " (auto-matched)"}
                        </span>
                      </div>
                    </div>
                  )}
                </TabsContent>

                <TabsContent value="chart" className="m-0">
                  {snapshot.image_data ? (
                    <div className="rounded-lg overflow-hidden border border-border">
                      <img
                        src={`data:image/png;base64,${snapshot.image_data}`}
                        alt="Chart snapshot"
                        className="w-full h-auto"
                      />
                    </div>
                  ) : (
                    <div className="text-center py-8 text-muted-foreground">
                      No chart image available
                    </div>
                  )}
                </TabsContent>

                {hasGroup && (
                  <TabsContent value="group" className="m-0 space-y-4">
                    {/* HTF Section - Higher Timeframes for Bias */}
                    {htfSnapshots.length > 0 && (
                      <div className="space-y-2">
                        <div className="flex items-center gap-2">
                          <ArrowUp className="w-4 h-4 text-blue-500" />
                          <h4 className="font-semibold text-sm">Higher Timeframes (Bias)</h4>
                        </div>
                        <div className="grid gap-2">
                          {htfSnapshots.map((gs) => (
                            <GroupSnapshotCard
                              key={gs.id}
                              snapshot={gs}
                              isSelected={selectedGroupTf === gs.timeframe}
                              onSelect={() => setSelectedGroupTf(gs.timeframe)}
                            />
                          ))}
                        </div>
                      </div>
                    )}

                    {/* LTF Section - Lower Timeframes for Entry */}
                    {ltfSnapshots.length > 0 && (
                      <div className="space-y-2">
                        <div className="flex items-center gap-2">
                          <ArrowDown className="w-4 h-4 text-emerald-500" />
                          <h4 className="font-semibold text-sm">Lower Timeframes (Entry)</h4>
                        </div>
                        <div className="grid gap-2">
                          {ltfSnapshots.map((gs) => (
                            <GroupSnapshotCard
                              key={gs.id}
                              snapshot={gs}
                              isSelected={selectedGroupTf === gs.timeframe}
                              onSelect={() => setSelectedGroupTf(gs.timeframe)}
                            />
                          ))}
                        </div>
                      </div>
                    )}

                    {/* Selected Timeframe Chart & Analysis */}
                    {viewedGroupSnapshot && (
                      <div className="space-y-4 pt-4 border-t border-border">
                        <div className="flex items-center justify-between">
                          <div className="flex items-center gap-2">
                            <Badge variant="outline" className="font-mono">{viewedGroupSnapshot.timeframe}</Badge>
                            <Badge variant={viewedGroupSnapshot.tf_type === "htf" ? "secondary" : "default"}>
                              {viewedGroupSnapshot.tf_type === "htf" ? "Bias" : "Entry"}
                            </Badge>
                          </div>
                          {viewedGroupSnapshot.trade_direction && viewedGroupSnapshot.trade_direction !== "none" && (
                            <Badge variant={viewedGroupSnapshot.trade_direction === "long" ? "default" : "destructive"}>
                              {viewedGroupSnapshot.trade_direction.toUpperCase()}
                            </Badge>
                          )}
                        </div>

                        {/* Chart Image */}
                        {viewedGroupSnapshot.image_data && (
                          <div className="rounded-lg overflow-hidden border border-border">
                            <img
                              src={`data:image/png;base64,${viewedGroupSnapshot.image_data}`}
                              alt={`${viewedGroupSnapshot.timeframe} chart`}
                              className="w-full h-auto"
                            />
                          </div>
                        )}

                        {/* Analysis Summary */}
                        {viewedGroupSnapshot.full_analysis_parsed && (
                          <div className="space-y-2">
                            <h5 className="text-sm font-semibold">Analysis</h5>
                            <p className="text-sm text-muted-foreground p-3 bg-muted/50 rounded-lg">
                              {viewedGroupSnapshot.full_analysis_parsed.overall_assessment}
                            </p>
                            {viewedGroupSnapshot.full_analysis_parsed.entry_logic?.valid_setup && (
                              <div className="p-3 bg-muted/50 rounded-lg space-y-1">
                                <div className="flex items-center justify-between text-sm">
                                  <span>Entry Zone</span>
                                  <span className="font-mono">{viewedGroupSnapshot.full_analysis_parsed.entry_logic.entry_zone}</span>
                                </div>
                                <div className="flex items-center justify-between text-sm">
                                  <span>Invalidation</span>
                                  <span className="font-mono">{viewedGroupSnapshot.full_analysis_parsed.entry_logic.invalidation_level}</span>
                                </div>
                                <div className="flex items-center justify-between text-sm">
                                  <span>Confidence</span>
                                  <span className="font-mono">{viewedGroupSnapshot.full_analysis_parsed.entry_logic.confidence}%</span>
                                </div>
                              </div>
                            )}
                          </div>
                        )}
                      </div>
                    )}

                    {!viewedGroupSnapshot && (
                      <div className="text-center py-8 text-muted-foreground">
                        <Clock className="w-8 h-8 mx-auto mb-2 opacity-50" />
                        <p className="text-sm">Select a timeframe above to view its chart and analysis</p>
                      </div>
                    )}
                  </TabsContent>
                )}

                {isAnalyzed && (
                  <TabsContent value="analysis" className="m-0 space-y-4">
                    {/* Overall Assessment */}
                    <div className="space-y-2">
                      <h4 className="font-semibold text-sm">Overall Assessment</h4>
                      <p className="text-sm text-muted-foreground p-3 bg-muted/50 rounded-lg">
                        {analysis?.overall_assessment}
                      </p>
                    </div>

                    {/* Market Structure */}
                    <div className="space-y-2">
                      <h4 className="font-semibold text-sm">Market Structure</h4>
                      <div className="p-3 bg-muted/50 rounded-lg space-y-2">
                        <div className="flex items-center gap-2">
                          <Badge variant="outline">{analysis?.market_structure.trend_state}</Badge>
                          {analysis?.market_structure.bos_detected && <Badge>BOS</Badge>}
                          {analysis?.market_structure.choch_detected && <Badge variant="secondary">CHOCH</Badge>}
                        </div>
                        {analysis?.market_structure.structure_points.length > 0 && (
                          <div className="text-xs text-muted-foreground">
                            {analysis.market_structure.structure_points.join(" • ")}
                          </div>
                        )}
                      </div>
                    </div>

                    {/* Confluences List */}
                    {analysis?.entry_logic.confluence_list && analysis.entry_logic.confluence_list.length > 0 && (
                      <div className="space-y-2">
                        <h4 className="font-semibold text-sm">Confluences</h4>
                        <ul className="space-y-1">
                          {analysis.entry_logic.confluence_list.map((conf, i) => (
                            <li key={i} className="flex items-start gap-2 text-sm">
                              <CheckCircle className="w-4 h-4 text-emerald-500 mt-0.5 shrink-0" />
                              {conf}
                            </li>
                          ))}
                        </ul>
                      </div>
                    )}

                    {/* Targets */}
                    {analysis?.entry_logic.targets && analysis.entry_logic.targets.length > 0 && (
                      <div className="space-y-2">
                        <h4 className="font-semibold text-sm">Targets</h4>
                        <div className="flex gap-2 flex-wrap">
                          {analysis.entry_logic.targets.map((target, i) => (
                            <Badge key={i} variant="outline" className="font-mono">
                              TP{i + 1}: {target}
                            </Badge>
                          ))}
                        </div>
                      </div>
                    )}
                  </TabsContent>
                )}

                {/* Deep Analysis Tab with AI-Generated Visual Breakdown */}
                {snapshot.image_data && (
                  <TabsContent value="deep" className="m-0 space-y-4">
                    {/* Visual Annotations - AI analyzes the chart image directly */}
                    <VisualAnnotations
                      imageData={snapshot.image_data}
                      annotations={annotations}
                      isLoading={generateAnnotationsMutation.isPending}
                      onGenerateAnnotations={handleGenerateAnnotations}
                    />

                    {/* Quick Analysis Summary - if analysis exists */}
                    {isAnalyzed && analysis && (
                      <div className="p-3 bg-muted/50 rounded-lg space-y-2 border border-border">
                        <div className="flex items-center justify-between">
                          <span className="text-sm font-semibold">Analysis Summary</span>
                          <Badge variant={analysis.entry_logic.valid_setup ? "default" : "secondary"}>
                            {analysis.entry_logic.valid_setup
                              ? `${analysis.entry_logic.trade_direction?.toUpperCase()} @ ${analysis.entry_logic.confidence}%`
                              : "No Setup"}
                          </Badge>
                        </div>
                        <p className="text-xs text-muted-foreground">{analysis.overall_assessment}</p>
                        {analysis.entry_logic.valid_setup && (
                          <div className="flex flex-wrap gap-2 pt-2 border-t border-border/50">
                            <Badge variant="outline" className="text-xs">
                              Entry: {analysis.entry_logic.entry_zone}
                            </Badge>
                            <Badge variant="outline" className="text-xs text-red-500 border-red-500/30">
                              SL: {analysis.entry_logic.invalidation_level}
                            </Badge>
                            {analysis.entry_logic.targets.map((t, i) => (
                              <Badge key={i} variant="outline" className="text-xs text-emerald-500 border-emerald-500/30">
                                TP{i + 1}: {t}
                              </Badge>
                            ))}
                          </div>
                        )}
                      </div>
                    )}
                  </TabsContent>
                )}

                <TabsContent value="notes" className="m-0 space-y-4">
                  <Textarea
                    placeholder="Add your notes about this setup..."
                    value={notes}
                    onChange={(e) => setNotes(e.target.value)}
                    className="min-h-[200px]"
                  />
                  <Button
                    onClick={handleSaveNotes}
                    disabled={updateNotesMutation.isPending || notes === (snapshot.user_notes || "")}
                    size="sm"
                  >
                    {updateNotesMutation.isPending && <Loader2 className="w-4 h-4 mr-2 animate-spin" />}
                    Save Notes
                  </Button>
                </TabsContent>
              </ScrollArea>
            </Tabs>
          </div>
        ) : (
          <div className="flex-1 flex items-center justify-center text-muted-foreground">
            Snapshot not found
          </div>
        )}
      </SheetContent>
    </Sheet>
  );
}
