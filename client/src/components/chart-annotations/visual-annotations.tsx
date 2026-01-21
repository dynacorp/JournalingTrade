import { useState, useRef, useEffect, useCallback } from "react";
import { cn } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogTitle,
} from "@/components/ui/dialog";
import { Loader2, Sparkles, Maximize2, X, RefreshCw } from "lucide-react";
import type { ChartAnnotation } from "@/hooks/use-chart-snapshots";

// Hide the default dialog close button in fullscreen mode
import "./visual-annotations.css";

interface VisualAnnotationsProps {
  imageData: string;
  annotations: ChartAnnotation[];
  isLoading?: boolean;
  onGenerateAnnotations?: () => void;
  onRegenerateAnnotations?: () => void;
  className?: string;
}

// Professional color scheme with gradients
const ANNOTATION_STYLES = {
  entry: {
    primary: "#22c55e",
    secondary: "#16a34a",
    glow: "rgba(34, 197, 94, 0.5)",
    icon: "▶",
    lineStyle: "solid",
  },
  target: {
    primary: "#10b981",
    secondary: "#059669",
    glow: "rgba(16, 185, 129, 0.4)",
    icon: "◎",
    lineStyle: "dashed",
  },
  support: {
    primary: "#22c55e",
    secondary: "#15803d",
    glow: "rgba(34, 197, 94, 0.4)",
    icon: "━",
    lineStyle: "solid",
  },
  resistance: {
    primary: "#ef4444",
    secondary: "#dc2626",
    glow: "rgba(239, 68, 68, 0.4)",
    icon: "━",
    lineStyle: "solid",
  },
  bos: {
    primary: "#3b82f6",
    secondary: "#2563eb",
    glow: "rgba(59, 130, 246, 0.5)",
    icon: "⚡",
    lineStyle: "solid",
  },
  choch: {
    primary: "#a855f7",
    secondary: "#9333ea",
    glow: "rgba(168, 85, 247, 0.5)",
    icon: "↻",
    lineStyle: "solid",
  },
  liquidity: {
    primary: "#f97316",
    secondary: "#ea580c",
    glow: "rgba(249, 115, 22, 0.5)",
    icon: "◆",
    lineStyle: "dotted",
  },
  fvg: {
    primary: "#eab308",
    secondary: "#ca8a04",
    glow: "rgba(234, 179, 8, 0.4)",
    icon: "▧",
    lineStyle: "solid",
  },
  orderblock: {
    primary: "#6366f1",
    secondary: "#4f46e5",
    glow: "rgba(99, 102, 241, 0.5)",
    icon: "▣",
    lineStyle: "solid",
  },
  sweep: {
    primary: "#06b6d4",
    secondary: "#0891b2",
    glow: "rgba(6, 182, 212, 0.5)",
    icon: "✓",
    lineStyle: "solid",
  },
} as const;

export function VisualAnnotations({
  imageData,
  annotations,
  isLoading = false,
  onGenerateAnnotations,
  onRegenerateAnnotations,
  className,
}: VisualAnnotationsProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const fullscreenContainerRef = useRef<HTMLDivElement>(null);
  const [dimensions, setDimensions] = useState({ width: 0, height: 0 });
  const [fullscreenDimensions, setFullscreenDimensions] = useState({ width: 0, height: 0 });
  const [isFullscreen, setIsFullscreen] = useState(false);
  const [hoveredAnnotation, setHoveredAnnotation] = useState<string | null>(null);

  const handleFullscreenImageLoad = useCallback(() => {
    const container = fullscreenContainerRef.current;
    if (!container) return;
    const rect = container.getBoundingClientRect();
    setFullscreenDimensions({ width: rect.width, height: rect.height });
  }, []);

  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    const updateDimensions = () => {
      const rect = container.getBoundingClientRect();
      setDimensions({ width: rect.width, height: rect.height });
    };

    updateDimensions();
    const observer = new ResizeObserver(updateDimensions);
    observer.observe(container);

    return () => observer.disconnect();
  }, []);

  useEffect(() => {
    if (!isFullscreen) {
      setFullscreenDimensions({ width: 0, height: 0 });
      return;
    }

    const container = fullscreenContainerRef.current;
    if (!container) return;

    const updateFullscreenDimensions = () => {
      const rect = container.getBoundingClientRect();
      if (rect.width > 0 && rect.height > 0) {
        setFullscreenDimensions({ width: rect.width, height: rect.height });
      }
    };

    const timeout1 = setTimeout(updateFullscreenDimensions, 50);
    const timeout2 = setTimeout(updateFullscreenDimensions, 150);
    const timeout3 = setTimeout(updateFullscreenDimensions, 300);

    const observer = new ResizeObserver(updateFullscreenDimensions);
    observer.observe(container);

    return () => {
      clearTimeout(timeout1);
      clearTimeout(timeout2);
      clearTimeout(timeout3);
      observer.disconnect();
    };
  }, [isFullscreen]);

  // Separate annotations by type for layered rendering
  const zoneAnnotations = annotations.filter(a =>
    a.type === "fvg" || a.type === "orderblock"
  );
  const lineAnnotations = annotations.filter(a =>
    a.lineY !== undefined && a.type !== "fvg" && a.type !== "orderblock"
  );
  const pointAnnotations = annotations.filter(a =>
    a.lineY === undefined && a.type !== "fvg" && a.type !== "orderblock"
  );

  return (
    <div className={cn("space-y-3", className)}>
      {/* Generate/Regenerate Annotations Button */}
      {onGenerateAnnotations && (
        <div className="flex gap-2">
          {annotations.length === 0 ? (
            <Button
              onClick={onGenerateAnnotations}
              disabled={isLoading}
              size="sm"
              className="w-full bg-gradient-to-r from-violet-600 to-indigo-600 hover:from-violet-700 hover:to-indigo-700"
            >
              {isLoading ? (
                <Loader2 className="w-4 h-4 mr-2 animate-spin" />
              ) : (
                <Sparkles className="w-4 h-4 mr-2" />
              )}
              {isLoading ? "Analyzing Chart..." : "Generate Professional Breakdown"}
            </Button>
          ) : (
            <Button
              onClick={onRegenerateAnnotations || onGenerateAnnotations}
              disabled={isLoading}
              size="sm"
              variant="outline"
              className="w-full border-violet-500/50 hover:bg-violet-500/10"
            >
              {isLoading ? (
                <Loader2 className="w-4 h-4 mr-2 animate-spin" />
              ) : (
                <RefreshCw className="w-4 h-4 mr-2" />
              )}
              {isLoading ? "Regenerating..." : "Regenerate Breakdown"}
            </Button>
          )}
        </div>
      )}

      {/* Chart with Annotations */}
      <div
        ref={containerRef}
        className="relative rounded-lg overflow-hidden border-2 border-border/50 bg-black cursor-pointer group shadow-xl"
        onClick={() => setIsFullscreen(true)}
      >
        <img
          src={`data:image/png;base64,${imageData}`}
          alt="Chart snapshot"
          className="w-full h-auto block"
        />

        {/* Fullscreen hint overlay */}
        <div className="absolute inset-0 bg-black/0 group-hover:bg-black/20 transition-colors flex items-center justify-center pointer-events-none">
          <div className="opacity-0 group-hover:opacity-100 transition-opacity bg-black/80 text-white px-4 py-2 rounded-lg flex items-center gap-2 backdrop-blur-sm border border-white/20">
            <Maximize2 className="w-4 h-4" />
            <span className="text-sm font-medium">Click to expand</span>
          </div>
        </div>

        {/* SVG Overlay for professional annotations */}
        {dimensions.width > 0 && annotations.length > 0 && (
          <ProfessionalAnnotationSVG
            annotations={annotations}
            zoneAnnotations={zoneAnnotations}
            lineAnnotations={lineAnnotations}
            dimensions={dimensions}
            hoveredAnnotation={hoveredAnnotation}
          />
        )}

        {/* HTML Overlay for annotation labels */}
        {dimensions.width > 0 && annotations.length > 0 && (
          <div className="absolute inset-0 pointer-events-none">
            {annotations.map((annotation) => {
              const x = (annotation.x / 100) * dimensions.width;
              const y = (annotation.y / 100) * dimensions.height;

              return (
                <ProfessionalAnnotationLabel
                  key={annotation.id}
                  annotation={annotation}
                  x={x}
                  y={y}
                  containerWidth={dimensions.width}
                  isHovered={hoveredAnnotation === annotation.id}
                  onHover={setHoveredAnnotation}
                />
              );
            })}
          </div>
        )}

        {/* Loading overlay */}
        {isLoading && (
          <div className="absolute inset-0 bg-black/60 backdrop-blur-sm flex items-center justify-center">
            <div className="flex flex-col items-center gap-3 text-white">
              <div className="relative">
                <Loader2 className="w-8 h-8 animate-spin text-violet-400" />
                <div className="absolute inset-0 blur-lg bg-violet-400/50 animate-pulse" />
              </div>
              <span className="text-sm font-medium">Analyzing chart structure...</span>
            </div>
          </div>
        )}

        {/* Empty state */}
        {!isLoading && annotations.length === 0 && (
          <div className="absolute inset-0 flex items-center justify-center bg-black/30 backdrop-blur-[1px]">
            <div className="text-center text-white/80 p-6 bg-black/40 rounded-xl border border-white/10">
              <Sparkles className="w-10 h-10 mx-auto mb-3 text-violet-400" />
              <p className="text-sm font-medium">Generate a professional chart breakdown</p>
              <p className="text-xs text-white/50 mt-1">AI-powered structure, levels, and zones</p>
            </div>
          </div>
        )}
      </div>

      {/* Annotation Legend */}
      {annotations.length > 0 && (
        <AnnotationLegend annotations={annotations} />
      )}

      {/* Fullscreen Dialog */}
      <Dialog open={isFullscreen} onOpenChange={setIsFullscreen}>
        <DialogContent className="fullscreen-chart-dialog max-w-[95vw] max-h-[95vh] w-auto h-auto p-0 bg-black/95 border-border overflow-hidden backdrop-blur-xl">
          <DialogTitle className="sr-only">Chart Breakdown Fullscreen View</DialogTitle>
          <div className="relative">
            {/* Close button */}
            <Button
              variant="ghost"
              size="icon"
              className="absolute top-3 right-3 z-50 bg-black/70 hover:bg-black/90 text-white border border-white/20"
              onClick={() => setIsFullscreen(false)}
            >
              <X className="w-5 h-5" />
            </Button>

            {/* Fullscreen chart with annotations */}
            <div
              ref={fullscreenContainerRef}
              className="relative"
            >
              <img
                src={`data:image/png;base64,${imageData}`}
                alt="Chart snapshot fullscreen"
                className="max-w-[95vw] max-h-[90vh] w-auto h-auto block"
                onLoad={handleFullscreenImageLoad}
              />

              {/* SVG Overlay for annotations in fullscreen */}
              {fullscreenDimensions.width > 0 && annotations.length > 0 && (
                <ProfessionalAnnotationSVG
                  annotations={annotations}
                  zoneAnnotations={zoneAnnotations}
                  lineAnnotations={lineAnnotations}
                  dimensions={fullscreenDimensions}
                  hoveredAnnotation={hoveredAnnotation}
                  isFullscreen
                />
              )}

              {/* HTML Overlay for annotation labels in fullscreen */}
              {fullscreenDimensions.width > 0 && annotations.length > 0 && (
                <div className="absolute inset-0 pointer-events-none">
                  {annotations.map((annotation) => {
                    const x = (annotation.x / 100) * fullscreenDimensions.width;
                    const y = (annotation.y / 100) * fullscreenDimensions.height;

                    return (
                      <ProfessionalAnnotationLabel
                        key={`fullscreen-${annotation.id}`}
                        annotation={annotation}
                        x={x}
                        y={y}
                        containerWidth={fullscreenDimensions.width}
                        isHovered={hoveredAnnotation === annotation.id}
                        onHover={setHoveredAnnotation}
                        isFullscreen
                      />
                    );
                  })}
                </div>
              )}
            </div>

            {/* Floating legend in fullscreen */}
            {annotations.length > 0 && (
              <div className="absolute bottom-4 left-4 right-4">
                <AnnotationLegend annotations={annotations} isFullscreen />
              </div>
            )}
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
}

// Professional SVG annotation rendering
interface ProfessionalAnnotationSVGProps {
  annotations: ChartAnnotation[];
  zoneAnnotations: ChartAnnotation[];
  lineAnnotations: ChartAnnotation[];
  dimensions: { width: number; height: number };
  hoveredAnnotation: string | null;
  isFullscreen?: boolean;
}

function ProfessionalAnnotationSVG({
  annotations,
  zoneAnnotations,
  lineAnnotations,
  dimensions,
  hoveredAnnotation,
  isFullscreen = false,
}: ProfessionalAnnotationSVGProps) {
  const strokeWidth = isFullscreen ? 3 : 2;
  const glowIntensity = isFullscreen ? 8 : 4;

  return (
    <svg
      className="absolute inset-0 w-full h-full pointer-events-none"
      viewBox={`0 0 ${dimensions.width} ${dimensions.height}`}
      preserveAspectRatio="none"
    >
      {/* SVG Definitions for effects */}
      <defs>
        {/* Glow filters for each annotation type */}
        {Object.entries(ANNOTATION_STYLES).map(([type, style]) => (
          <filter key={`glow-${type}`} id={`glow-${type}`} x="-50%" y="-50%" width="200%" height="200%">
            <feGaussianBlur stdDeviation={glowIntensity} result="blur" />
            <feFlood floodColor={style.glow} result="color" />
            <feComposite in="color" in2="blur" operator="in" result="glow" />
            <feMerge>
              <feMergeNode in="glow" />
              <feMergeNode in="SourceGraphic" />
            </feMerge>
          </filter>
        ))}

        {/* Zone pattern fills */}
        <pattern id="zone-pattern-bullish" patternUnits="userSpaceOnUse" width="8" height="8">
          <path d="M-2,2 l4,-4 M0,8 l8,-8 M6,10 l4,-4" stroke="rgba(34, 197, 94, 0.3)" strokeWidth="1"/>
        </pattern>
        <pattern id="zone-pattern-bearish" patternUnits="userSpaceOnUse" width="8" height="8">
          <path d="M-2,2 l4,-4 M0,8 l8,-8 M6,10 l4,-4" stroke="rgba(239, 68, 68, 0.3)" strokeWidth="1"/>
        </pattern>
        <pattern id="zone-pattern-fvg" patternUnits="userSpaceOnUse" width="6" height="6">
          <path d="M0,0 L6,6 M6,0 L0,6" stroke="rgba(234, 179, 8, 0.4)" strokeWidth="1"/>
        </pattern>
        <pattern id="zone-pattern-ob" patternUnits="userSpaceOnUse" width="10" height="10">
          <rect width="10" height="10" fill="rgba(99, 102, 241, 0.15)"/>
          <path d="M0,5 L10,5" stroke="rgba(99, 102, 241, 0.3)" strokeWidth="1"/>
        </pattern>
      </defs>

      {/* Layer 1: Zone backgrounds (FVG, Order Blocks) */}
      {zoneAnnotations.map((annotation) => {
        const y = (annotation.y / 100) * dimensions.height;
        const lineY = annotation.lineY ? (annotation.lineY / 100) * dimensions.height : y;
        const zoneHeight = Math.abs(lineY - y) || dimensions.height * 0.03;
        const topY = Math.min(y, lineY);
        const style = ANNOTATION_STYLES[annotation.type as keyof typeof ANNOTATION_STYLES] || ANNOTATION_STYLES.support;
        const isHovered = hoveredAnnotation === annotation.id;

        const patternId = annotation.type === "fvg" ? "zone-pattern-fvg" : "zone-pattern-ob";

        return (
          <g key={`zone-${annotation.id}`}>
            {/* Zone fill with pattern */}
            <rect
              x={0}
              y={topY}
              width={dimensions.width}
              height={zoneHeight}
              fill={`url(#${patternId})`}
              opacity={isHovered ? 0.9 : 0.7}
            />
            {/* Zone border top */}
            <line
              x1={0}
              y1={topY}
              x2={dimensions.width}
              y2={topY}
              stroke={style.primary}
              strokeWidth={strokeWidth}
              opacity={isHovered ? 1 : 0.8}
              filter={isHovered ? `url(#glow-${annotation.type})` : undefined}
            />
            {/* Zone border bottom */}
            <line
              x1={0}
              y1={topY + zoneHeight}
              x2={dimensions.width}
              y2={topY + zoneHeight}
              stroke={style.primary}
              strokeWidth={strokeWidth}
              opacity={isHovered ? 1 : 0.8}
            />
          </g>
        );
      })}

      {/* Layer 2: Horizontal level lines */}
      {lineAnnotations.map((annotation) => {
        const y = (annotation.lineY! / 100) * dimensions.height;
        const style = ANNOTATION_STYLES[annotation.type as keyof typeof ANNOTATION_STYLES] || ANNOTATION_STYLES.support;
        const isHovered = hoveredAnnotation === annotation.id;

        const dashArray = style.lineStyle === "dashed"
          ? "12 6"
          : style.lineStyle === "dotted"
            ? "4 4"
            : "none";

        return (
          <g key={`line-${annotation.id}`}>
            {/* Glow effect line (background) */}
            <line
              x1={0}
              y1={y}
              x2={dimensions.width}
              y2={y}
              stroke={style.glow}
              strokeWidth={strokeWidth * 4}
              opacity={isHovered ? 0.6 : 0.3}
            />
            {/* Main line */}
            <line
              x1={0}
              y1={y}
              x2={dimensions.width}
              y2={y}
              stroke={style.primary}
              strokeWidth={strokeWidth}
              strokeDasharray={dashArray}
              opacity={isHovered ? 1 : 0.9}
              filter={isHovered ? `url(#glow-${annotation.type})` : undefined}
              style={{ transition: "all 0.2s ease" }}
            />
            {/* Price marker circles at edges */}
            <circle
              cx={10}
              cy={y}
              r={isFullscreen ? 5 : 3}
              fill={style.primary}
              opacity={0.9}
            />
            <circle
              cx={dimensions.width - 10}
              cy={y}
              r={isFullscreen ? 5 : 3}
              fill={style.primary}
              opacity={0.9}
            />
          </g>
        );
      })}

      {/* Layer 3: Point markers (BOS, CHOCH, Sweep) */}
      {annotations.filter(a => a.type === "bos" || a.type === "choch" || a.type === "sweep").map((annotation) => {
        const x = (annotation.x / 100) * dimensions.width;
        const y = (annotation.y / 100) * dimensions.height;
        const style = ANNOTATION_STYLES[annotation.type as keyof typeof ANNOTATION_STYLES];
        const isHovered = hoveredAnnotation === annotation.id;
        const size = isFullscreen ? 12 : 8;

        return (
          <g key={`marker-${annotation.id}`}>
            {/* Pulsing circle background */}
            <circle
              cx={x}
              cy={y}
              r={size * 2}
              fill={style.glow}
              opacity={isHovered ? 0.6 : 0.3}
            >
              <animate
                attributeName="r"
                values={`${size * 1.5};${size * 2.5};${size * 1.5}`}
                dur="2s"
                repeatCount="indefinite"
              />
              <animate
                attributeName="opacity"
                values="0.3;0.5;0.3"
                dur="2s"
                repeatCount="indefinite"
              />
            </circle>
            {/* Main marker */}
            <circle
              cx={x}
              cy={y}
              r={size}
              fill={style.primary}
              stroke={style.secondary}
              strokeWidth={2}
              filter={`url(#glow-${annotation.type})`}
            />
            {/* Inner icon representation */}
            {annotation.type === "bos" && (
              <polygon
                points={`${x},${y - size/2} ${x + size/2},${y + size/2} ${x - size/2},${y + size/2}`}
                fill="white"
                opacity={0.9}
              />
            )}
            {annotation.type === "choch" && (
              <path
                d={`M${x - size/2},${y} A${size/2},${size/2} 0 1,1 ${x + size/2},${y}`}
                fill="none"
                stroke="white"
                strokeWidth={2}
              />
            )}
            {annotation.type === "sweep" && (
              <path
                d={`M${x - size/2},${y} L${x - size/4},${y + size/2} L${x + size/2},${y - size/2}`}
                fill="none"
                stroke="white"
                strokeWidth={2}
                strokeLinecap="round"
              />
            )}
          </g>
        );
      })}
    </svg>
  );
}

// Professional annotation label
interface ProfessionalAnnotationLabelProps {
  annotation: ChartAnnotation;
  x: number;
  y: number;
  containerWidth: number;
  isHovered: boolean;
  onHover: (id: string | null) => void;
  isFullscreen?: boolean;
}

function ProfessionalAnnotationLabel({
  annotation,
  x,
  y,
  containerWidth,
  isHovered,
  onHover,
  isFullscreen = false
}: ProfessionalAnnotationLabelProps) {
  const isRightSide = x > containerWidth * 0.6;
  const labelWidth = isFullscreen ? 220 : 160;

  const adjustedX = isRightSide
    ? Math.min(x - labelWidth - 20, containerWidth - labelWidth - 10)
    : Math.max(x + 20, 10);

  const style = ANNOTATION_STYLES[annotation.type as keyof typeof ANNOTATION_STYLES] || ANNOTATION_STYLES.support;

  return (
    <div
      className="absolute pointer-events-auto transition-all duration-200"
      style={{
        left: adjustedX,
        top: y,
        transform: `translateY(-50%) scale(${isHovered ? 1.05 : 1})`,
        maxWidth: labelWidth,
        zIndex: isHovered ? 50 : 10,
      }}
      onMouseEnter={() => onHover(annotation.id)}
      onMouseLeave={() => onHover(null)}
    >
      <div
        className={cn(
          "rounded-lg border-2 font-medium shadow-2xl backdrop-blur-sm transition-all duration-200",
          isFullscreen ? "px-4 py-2" : "px-3 py-1.5",
          isHovered && "ring-2 ring-white/30"
        )}
        style={{
          background: `linear-gradient(135deg, ${style.primary}ee, ${style.secondary}dd)`,
          borderColor: style.primary,
          boxShadow: isHovered
            ? `0 0 20px ${style.glow}, 0 4px 12px rgba(0,0,0,0.4)`
            : `0 4px 12px rgba(0,0,0,0.3)`,
        }}
        title={annotation.description}
      >
        {/* Type icon and label */}
        <div className="flex items-center gap-2">
          <span className={cn("opacity-80", isFullscreen ? "text-base" : "text-sm")}>
            {style.icon}
          </span>
          <span className={cn(
            "font-bold text-white truncate",
            isFullscreen ? "text-sm" : "text-xs"
          )}>
            {annotation.label}
          </span>
        </div>

        {/* Price display */}
        {annotation.price && (
          <div className={cn(
            "font-mono text-white/90 mt-0.5",
            isFullscreen ? "text-sm" : "text-[11px]"
          )}>
            @ {annotation.price.toFixed(annotation.price >= 100 ? 2 : 5)}
          </div>
        )}

        {/* Description on hover */}
        {isHovered && annotation.description && (
          <div className={cn(
            "text-white/80 mt-1 border-t border-white/20 pt-1",
            isFullscreen ? "text-xs" : "text-[10px]"
          )}>
            {annotation.description}
          </div>
        )}
      </div>

      {/* Connector line to actual position */}
      <svg
        className="absolute top-1/2 -translate-y-1/2 pointer-events-none"
        style={{
          left: isRightSide ? "100%" : "auto",
          right: isRightSide ? "auto" : "100%",
          width: Math.abs(x - adjustedX) + 30,
          height: 20,
          overflow: "visible",
        }}
      >
        <line
          x1={isRightSide ? 0 : Math.abs(x - adjustedX) + 20}
          y1={10}
          x2={isRightSide ? Math.abs(x - adjustedX) + 20 : 0}
          y2={10}
          stroke={style.primary}
          strokeWidth={isFullscreen ? 2 : 1.5}
          strokeDasharray="6 3"
          opacity={0.8}
        />
        {/* Arrow head */}
        <circle
          cx={isRightSide ? Math.abs(x - adjustedX) + 20 : 0}
          cy={10}
          r={isFullscreen ? 4 : 3}
          fill={style.primary}
        />
      </svg>
    </div>
  );
}

// Annotation Legend component
interface AnnotationLegendProps {
  annotations: ChartAnnotation[];
  isFullscreen?: boolean;
}

function AnnotationLegend({ annotations, isFullscreen = false }: AnnotationLegendProps) {
  // Count annotations by type
  const typeCounts = annotations.reduce((acc, a) => {
    acc[a.type] = (acc[a.type] || 0) + 1;
    return acc;
  }, {} as Record<string, number>);

  const typeLabels: Record<string, string> = {
    entry: "Entry",
    target: "Target",
    support: "Support",
    resistance: "Resistance",
    bos: "BOS",
    choch: "CHOCH",
    liquidity: "Liquidity",
    fvg: "FVG",
    orderblock: "Order Block",
    sweep: "Sweep",
  };

  return (
    <div className={cn(
      "flex flex-wrap gap-2",
      isFullscreen
        ? "bg-black/70 backdrop-blur-md p-3 rounded-lg border border-white/10"
        : "text-xs"
    )}>
      {Object.entries(typeCounts).map(([type, count]) => {
        const style = ANNOTATION_STYLES[type as keyof typeof ANNOTATION_STYLES];
        if (!style) return null;

        return (
          <div
            key={type}
            className={cn(
              "flex items-center gap-1.5 px-2 py-1 rounded-md",
              isFullscreen ? "bg-white/10" : "bg-muted/50"
            )}
          >
            <div
              className="w-3 h-3 rounded-sm"
              style={{ backgroundColor: style.primary }}
            />
            <span className={cn(
              "font-medium",
              isFullscreen ? "text-white text-sm" : "text-muted-foreground"
            )}>
              {typeLabels[type] || type}
            </span>
            <span className={cn(
              "font-mono",
              isFullscreen ? "text-white/60 text-xs" : "text-muted-foreground/60"
            )}>
              ×{count}
            </span>
          </div>
        );
      })}
      <div className={cn(
        "ml-auto font-medium",
        isFullscreen ? "text-white/70 text-sm" : "text-muted-foreground"
      )}>
        {annotations.length} annotations
      </div>
    </div>
  );
}
