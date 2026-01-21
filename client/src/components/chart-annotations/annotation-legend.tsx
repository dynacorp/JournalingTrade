import type { AnnotationSettings } from "./annotated-chart";

interface AnnotationLegendProps {
  annotations: AnnotationSettings;
}

interface LegendItem {
  key: keyof AnnotationSettings;
  label: string;
  color: string;
  style: "solid" | "dashed" | "dotted" | "fill";
}

const legendItems: LegendItem[] = [
  { key: "levels", label: "Resistance", color: "#ef4444", style: "solid" },
  { key: "levels", label: "Support", color: "#22c55e", style: "solid" },
  { key: "levels", label: "S/R Flip", color: "#a855f7", style: "dashed" },
  { key: "liquidity", label: "Equal Highs", color: "#f97316", style: "dotted" },
  { key: "liquidity", label: "Equal Lows", color: "#06b6d4", style: "dotted" },
  { key: "orderBlocks", label: "Order Block", color: "#3b82f6", style: "fill" },
  { key: "imbalances", label: "FVG Zone", color: "#eab308", style: "fill" },
  { key: "entryZone", label: "Entry Zone", color: "#22c55e", style: "fill" },
  { key: "entryZone", label: "Invalidation", color: "#dc2626", style: "dashed" },
  { key: "targets", label: "Targets", color: "#10b981", style: "dashed" },
];

function LegendLine({ item }: { item: LegendItem }) {
  const { label, color, style } = item;

  return (
    <div className="flex items-center gap-2 text-xs">
      {style === "solid" && (
        <div className="w-5 h-0.5" style={{ backgroundColor: color }} />
      )}
      {style === "dashed" && (
        <div
          className="w-5 h-0.5"
          style={{
            backgroundImage: `repeating-linear-gradient(to right, ${color} 0, ${color} 3px, transparent 3px, transparent 5px)`,
          }}
        />
      )}
      {style === "dotted" && (
        <div
          className="w-5 h-0.5"
          style={{
            backgroundImage: `repeating-linear-gradient(to right, ${color} 0, ${color} 2px, transparent 2px, transparent 4px)`,
          }}
        />
      )}
      {style === "fill" && (
        <div
          className="w-4 h-3 rounded-sm border"
          style={{
            backgroundColor: `${color}30`,
            borderColor: color,
          }}
        />
      )}
      <span className="text-muted-foreground">{label}</span>
    </div>
  );
}

export function AnnotationLegend({ annotations }: AnnotationLegendProps) {
  // Filter legend items based on active annotations
  const activeItems = legendItems.filter((item) => annotations[item.key]);

  if (activeItems.length === 0) return null;

  return (
    <div className="flex flex-wrap gap-x-4 gap-y-1.5 p-2 bg-muted/30 rounded-lg border border-border">
      {activeItems.map((item, i) => (
        <LegendLine key={`${item.key}-${item.label}-${i}`} item={item} />
      ))}
    </div>
  );
}
