import { useState, useRef, useEffect } from "react";
import { cn } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { Loader2, Sparkles } from "lucide-react";
import type { ChartAnnotation } from "@/hooks/use-chart-snapshots";

interface VisualAnnotationsProps {
  imageData: string;
  annotations: ChartAnnotation[];
  isLoading?: boolean;
  onGenerateAnnotations?: () => void;
  className?: string;
}

export function VisualAnnotations({
  imageData,
  annotations,
  isLoading = false,
  onGenerateAnnotations,
  className,
}: VisualAnnotationsProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const [dimensions, setDimensions] = useState({ width: 0, height: 0 });

  // Update dimensions when container resizes
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

  // Group annotations by whether they have horizontal lines
  const lineAnnotations = annotations.filter(a => a.lineY !== undefined);
  const pointAnnotations = annotations.filter(a => a.lineY === undefined);

  return (
    <div className={cn("space-y-3", className)}>
      {/* Generate Annotations Button */}
      {onGenerateAnnotations && (
        <Button
          onClick={onGenerateAnnotations}
          disabled={isLoading}
          size="sm"
          className="w-full"
        >
          {isLoading ? (
            <Loader2 className="w-4 h-4 mr-2 animate-spin" />
          ) : (
            <Sparkles className="w-4 h-4 mr-2" />
          )}
          {isLoading ? "Generating Breakdown..." : "Generate Visual Breakdown"}
        </Button>
      )}

      {/* Chart with Annotations */}
      <div
        ref={containerRef}
        className="relative rounded-lg overflow-hidden border border-border bg-black"
      >
        <img
          src={`data:image/png;base64,${imageData}`}
          alt="Chart snapshot"
          className="w-full h-auto block"
        />

        {/* SVG Overlay for annotations */}
        {dimensions.width > 0 && annotations.length > 0 && (
          <svg
            className="absolute inset-0 w-full h-full pointer-events-none"
            viewBox={`0 0 ${dimensions.width} ${dimensions.height}`}
            preserveAspectRatio="none"
          >
            {/* Horizontal lines for level annotations */}
            {lineAnnotations.map((annotation) => {
              const y = (annotation.lineY! / 100) * dimensions.height;
              return (
                <line
                  key={`line-${annotation.id}`}
                  x1={0}
                  y1={y}
                  x2={dimensions.width}
                  y2={y}
                  stroke={annotation.color}
                  strokeWidth="1"
                  strokeOpacity="0.8"
                />
              );
            })}
          </svg>
        )}

        {/* HTML Overlay for annotation labels */}
        {dimensions.width > 0 && annotations.length > 0 && (
          <div className="absolute inset-0 pointer-events-none">
            {annotations.map((annotation) => {
              const x = (annotation.x / 100) * dimensions.width;
              const y = (annotation.y / 100) * dimensions.height;

              return (
                <AnnotationLabel
                  key={annotation.id}
                  annotation={annotation}
                  x={x}
                  y={y}
                  containerWidth={dimensions.width}
                />
              );
            })}
          </div>
        )}

        {/* Loading overlay */}
        {isLoading && (
          <div className="absolute inset-0 bg-black/50 flex items-center justify-center">
            <div className="flex items-center gap-2 text-white">
              <Loader2 className="w-5 h-5 animate-spin" />
              <span className="text-sm">Analyzing chart...</span>
            </div>
          </div>
        )}

        {/* Empty state */}
        {!isLoading && annotations.length === 0 && (
          <div className="absolute inset-0 flex items-center justify-center">
            <div className="text-center text-white/70 p-4">
              <Sparkles className="w-8 h-8 mx-auto mb-2 opacity-50" />
              <p className="text-sm">Click "Generate Visual Breakdown" to annotate this chart</p>
            </div>
          </div>
        )}
      </div>

      {/* Summary */}
      {annotations.length > 0 && (
        <div className="text-xs text-muted-foreground">
          {annotations.length} annotations generated
        </div>
      )}
    </div>
  );
}

interface AnnotationLabelProps {
  annotation: ChartAnnotation;
  x: number;
  y: number;
  containerWidth: number;
}

function AnnotationLabel({ annotation, x, y, containerWidth }: AnnotationLabelProps) {
  // Determine if label should be on left or right based on position
  const isRightSide = x > containerWidth / 2;

  // Adjust position to keep label within bounds
  const labelWidth = Math.min(200, containerWidth * 0.35);
  const adjustedX = isRightSide
    ? Math.min(x, containerWidth - labelWidth - 10)
    : Math.max(x, 10);

  const getTypeStyles = () => {
    switch (annotation.type) {
      case "entry":
        return "bg-emerald-500/90 border-emerald-400 text-white";
      case "target":
        return "bg-emerald-600/90 border-emerald-500 text-white";
      case "support":
        return "bg-green-500/90 border-green-400 text-white";
      case "resistance":
        return "bg-red-500/90 border-red-400 text-white";
      case "bos":
        return "bg-blue-500/90 border-blue-400 text-white";
      case "choch":
        return "bg-purple-500/90 border-purple-400 text-white";
      case "liquidity":
        return "bg-orange-500/90 border-orange-400 text-white";
      case "fvg":
        return "bg-yellow-500/90 border-yellow-400 text-black";
      case "orderblock":
        return "bg-blue-600/90 border-blue-500 text-white";
      case "sweep":
        return "bg-cyan-500/90 border-cyan-400 text-white";
      default:
        return "bg-gray-700/90 border-gray-600 text-white";
    }
  };

  return (
    <div
      className="absolute pointer-events-auto"
      style={{
        left: adjustedX,
        top: y,
        transform: "translateY(-50%)",
        maxWidth: labelWidth,
      }}
    >
      <div
        className={cn(
          "px-2 py-1 rounded border text-xs font-medium shadow-lg",
          getTypeStyles()
        )}
        title={annotation.description}
      >
        <div className="font-semibold truncate">{annotation.label}</div>
        {annotation.price && (
          <div className="font-mono text-[10px] opacity-90">
            {annotation.price.toFixed(annotation.price >= 100 ? 2 : 5)}
          </div>
        )}
      </div>
      {/* Connector line to the actual position if label was adjusted */}
      {Math.abs(adjustedX - x) > 20 && (
        <svg
          className="absolute top-1/2 -translate-y-1/2 pointer-events-none"
          style={{
            left: isRightSide ? "auto" : "100%",
            right: isRightSide ? "100%" : "auto",
            width: Math.abs(x - adjustedX) + 10,
            height: 2,
          }}
        >
          <line
            x1={isRightSide ? Math.abs(x - adjustedX) : 0}
            y1={1}
            x2={isRightSide ? 0 : Math.abs(x - adjustedX)}
            y2={1}
            stroke={annotation.color}
            strokeWidth="1"
            strokeDasharray="3 2"
          />
        </svg>
      )}
    </div>
  );
}
