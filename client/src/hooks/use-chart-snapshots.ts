import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { apiRequest } from "@/lib/queryClient";
import type { ChartSnapshot, ChartSnapshotStatus, FullAnalysisResult } from "@shared/schema";

export type TradingStyle = "daytrading" | "swing";

export interface ChartSnapshotListItem extends Omit<ChartSnapshot, "image_data"> {
  has_image: boolean;
}

export interface GroupSnapshotSummary {
  id: number;
  timeframe: string;
  tf_type: string | null;
  status: string;
  pre_analysis_score: number | null;
  pre_analysis_bias: string | null;
  confluence_score: number | null;
  trade_direction: string | null;
}

export interface ChartSnapshotWithParsedAnalysis extends ChartSnapshot {
  full_analysis_parsed: FullAnalysisResult | null;
  group_snapshots?: GroupSnapshotSummary[] | null;
  visual_annotations_parsed?: ChartAnnotation[] | null;
}

export interface GroupedChartSnapshot extends ChartSnapshot {
  full_analysis_parsed: FullAnalysisResult | null;
  visual_annotations_parsed?: ChartAnnotation[] | null;
}

interface ChartSnapshotFilters {
  status?: ChartSnapshotStatus;
  symbol?: string;
  timeframe?: string;
  start_date?: string;
  end_date?: string;
  account_id?: string;
}

interface ChartSnapshotStats {
  pending: number;
  queued: number;
  analyzed: number;
  high_score_count: number;
}

export function useChartSnapshots(filters?: ChartSnapshotFilters) {
  return useQuery<ChartSnapshotListItem[]>({
    queryKey: ["chart-snapshots", filters],
    queryFn: async () => {
      const params = new URLSearchParams();
      if (filters?.status) params.set("status", filters.status);
      if (filters?.symbol) params.set("symbol", filters.symbol);
      if (filters?.timeframe) params.set("timeframe", filters.timeframe);
      if (filters?.start_date) params.set("start_date", filters.start_date);
      if (filters?.end_date) params.set("end_date", filters.end_date);
      if (filters?.account_id) params.set("account_id", filters.account_id);

      const queryString = params.toString();
      const url = `/api/chart-snapshots${queryString ? `?${queryString}` : ""}`;
      const res = await apiRequest("GET", url);
      return res.json();
    },
  });
}

export function useChartSnapshot(id: number | null) {
  return useQuery<ChartSnapshotWithParsedAnalysis>({
    queryKey: ["chart-snapshot", id],
    queryFn: async () => {
      const res = await apiRequest("GET", `/api/chart-snapshots/${id}`);
      return res.json();
    },
    enabled: id !== null,
  });
}

export function useChartSnapshotStats() {
  return useQuery<ChartSnapshotStats>({
    queryKey: ["chart-snapshot-stats"],
    queryFn: async () => {
      const res = await apiRequest("GET", "/api/chart-snapshots/stats");
      return res.json();
    },
  });
}

export function useApproveSnapshot() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (id: number) => {
      const res = await apiRequest("POST", `/api/chart-snapshots/${id}/approve`);
      return res.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["chart-snapshots"] });
      queryClient.invalidateQueries({ queryKey: ["chart-snapshot"] });
      queryClient.invalidateQueries({ queryKey: ["chart-snapshot-stats"] });
    },
  });
}

export function useDiscardSnapshot() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (id: number) => {
      const res = await apiRequest("POST", `/api/chart-snapshots/${id}/discard`);
      return res.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["chart-snapshots"] });
      queryClient.invalidateQueries({ queryKey: ["chart-snapshot"] });
      queryClient.invalidateQueries({ queryKey: ["chart-snapshot-stats"] });
    },
  });
}

export function useAnalyzeSnapshot() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({ id, tradingStyle }: { id: number; tradingStyle?: TradingStyle }) => {
      const res = await apiRequest("POST", `/api/chart-snapshots/${id}/analyze`, { tradingStyle });
      return res.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["chart-snapshots"] });
      queryClient.invalidateQueries({ queryKey: ["chart-snapshot"] });
      queryClient.invalidateQueries({ queryKey: ["chart-snapshot-stats"] });
    },
  });
}

export function useLinkSnapshotToTrade() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({ snapshotId, tradeId }: { snapshotId: number; tradeId: number }) => {
      const res = await apiRequest("POST", `/api/chart-snapshots/${snapshotId}/link-trade`, {
        trade_id: tradeId,
      });
      return res.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["chart-snapshots"] });
      queryClient.invalidateQueries({ queryKey: ["chart-snapshot"] });
    },
  });
}

export function useUnlinkSnapshotFromTrade() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (snapshotId: number) => {
      const res = await apiRequest("POST", `/api/chart-snapshots/${snapshotId}/unlink-trade`);
      return res.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["chart-snapshots"] });
      queryClient.invalidateQueries({ queryKey: ["chart-snapshot"] });
    },
  });
}

export function useUpdateSnapshotNotes() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({ id, notes }: { id: number; notes: string }) => {
      const res = await apiRequest("PATCH", `/api/chart-snapshots/${id}`, {
        user_notes: notes,
      });
      return res.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["chart-snapshot"] });
    },
  });
}

export function useMarkJournalCandidate() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({ id, isCandidate }: { id: number; isCandidate: boolean }) => {
      const res = await apiRequest("POST", `/api/chart-snapshots/${id}/mark-journal`, {
        is_journal_candidate: isCandidate,
      });
      return res.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["chart-snapshots"] });
      queryClient.invalidateQueries({ queryKey: ["chart-snapshot"] });
    },
  });
}

// ==================== GROUPED SNAPSHOT HOOKS ====================

export function useChartSnapshotGroup(groupId: string | null) {
  return useQuery<GroupedChartSnapshot[]>({
    queryKey: ["chart-snapshot-group", groupId],
    queryFn: async () => {
      const res = await apiRequest("GET", `/api/chart-snapshots/group/${groupId}`);
      return res.json();
    },
    enabled: !!groupId,
  });
}

export function useAnalyzeGroup() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({ groupId, tradingStyle }: { groupId: string; tradingStyle?: TradingStyle }) => {
      const res = await apiRequest("POST", `/api/chart-snapshots/group/${groupId}/analyze`, { tradingStyle });
      return res.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["chart-snapshots"] });
      queryClient.invalidateQueries({ queryKey: ["chart-snapshot"] });
      queryClient.invalidateQueries({ queryKey: ["chart-snapshot-group"] });
      queryClient.invalidateQueries({ queryKey: ["chart-snapshot-stats"] });
    },
  });
}

// ==================== DELETE SNAPSHOT HOOKS ====================

export function useDeleteSnapshot() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (id: number) => {
      const res = await apiRequest("DELETE", `/api/chart-snapshots/${id}`);
      return res.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["chart-snapshots"] });
      queryClient.invalidateQueries({ queryKey: ["chart-snapshot"] });
      queryClient.invalidateQueries({ queryKey: ["chart-snapshot-group"] });
      queryClient.invalidateQueries({ queryKey: ["chart-snapshot-stats"] });
    },
  });
}

export function useDeleteAllSnapshots() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (filters?: { status?: string; symbol?: string; timeframe?: string }) => {
      const params = new URLSearchParams();
      if (filters?.status) params.set("status", filters.status);
      if (filters?.symbol) params.set("symbol", filters.symbol);
      if (filters?.timeframe) params.set("timeframe", filters.timeframe);

      const queryString = params.toString();
      const url = `/api/chart-snapshots${queryString ? `?${queryString}` : ""}`;
      console.log("Deleting snapshots, URL:", url);
      const res = await apiRequest("DELETE", url);
      console.log("Response status:", res.status);
      const data = await res.json();
      console.log("Response data:", data);
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["chart-snapshots"] });
      queryClient.invalidateQueries({ queryKey: ["chart-snapshot"] });
      queryClient.invalidateQueries({ queryKey: ["chart-snapshot-group"] });
      queryClient.invalidateQueries({ queryKey: ["chart-snapshot-stats"] });
    },
  });
}

// ==================== CHART ANNOTATION HOOKS ====================

export interface ChartAnnotation {
  id: string;
  label: string;
  description: string;
  type: "entry" | "target" | "support" | "resistance" | "bos" | "choch" | "liquidity" | "fvg" | "orderblock" | "sweep";
  x: number;
  y: number;
  lineY?: number;
  price?: number;
  color: string;
}

export interface ChartAnnotationResult {
  snapshot_id: number;
  symbol: string;
  timeframe: string;
  annotations: ChartAnnotation[];
  summary: string;
  cached?: boolean;
}

export function useGenerateAnnotations() {
  const queryClient = useQueryClient();

  return useMutation<ChartAnnotationResult, Error, { snapshotId: number; force?: boolean; tradingStyle?: TradingStyle }>({
    mutationFn: async ({ snapshotId, force, tradingStyle }) => {
      const res = await apiRequest("POST", `/api/chart-snapshots/${snapshotId}/annotate`, { force, tradingStyle });
      return res.json();
    },
    onSuccess: (_, { snapshotId }) => {
      queryClient.invalidateQueries({ queryKey: ["chart-snapshot", snapshotId] });
      queryClient.invalidateQueries({ queryKey: ["chart-snapshot-group"] });
    },
  });
}
