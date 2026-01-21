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

  // Recalculate fullscreen dimensions when image loads
  const handleFullscreenImageLoad = useCallback(() => {
    const container = fullscreenContainerRef.current;
    if (!container) return;
    const rect = container.getBoundingClientRect();
    setFullscreenDimensions({ width: rect.width, height: rect.height });
  }, []);

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

  // Update fullscreen dimensions when dialog opens
  useEffect(() => {
    if (!isFullscreen) {
      // Reset dimensions when closing
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

    // Multiple delayed attempts to catch when dialog and image are ready
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

  // Group annotations by whether they have horizontal lines
  const lineAnnotations = annotations.filter(a => a.lineY !== undefined);
  const pointAnnotations = annotations.filter(a => a.lineY === undefined);

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
              className="w-full"
            >
              {isLoading ? (
                <Loader2 className="w-4 h-4 mr-2 animate-spin" />
              ) : (
                <Sparkles className="w-4 h-4 mr-2" />
              )}
              {isLoading ? "Generating Breakdown..." : "Generate Visual Breakdown"}
            </Button>
          ) : (
            <Button
              onClick={onRegenerateAnnotations || onGenerateAnnotations}
              disabled={isLoading}
              size="sm"
              variant="outline"
              className="w-full"
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
        className="relative rounded-lg overflow-hidden border border-border bg-black cursor-pointer group"
        onClick={() => setIsFullscreen(true)}
      >
        <img
          src={`data:image/png;base64,${imageData}`}
          alt="Chart snapshot"
          className="w-full h-auto block"
        />

        {/* Fullscreen hint overlay */}
        <div className="absolute inset-0 bg-black/0 group-hover:bg-black/20 transition-colors flex items-center justify-center pointer-events-none">
          <div className="opacity-0 group-hover:opacity-100 transition-opacity bg-black/70 text-white px-3 py-2 rounded-lg flex items-center gap-2">
            <Maximize2 className="w-4 h-4" />
            <span className="text-sm">Click to view fullscreen</span>
          </div>
        </div>

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

      {/* Fullscreen Dialog */}
      <Dialog open={isFullscreen} onOpenChange={setIsFullscreen}>
        <DialogContent className="fullscreen-chart-dialog max-w-[95vw] max-h-[95vh] w-auto h-auto p-0 bg-black border-border overflow-hidden">
          <DialogTitle className="sr-only">Chart Breakdown Fullscreen View</DialogTitle>
          <div className="relative">
            {/* Close button */}
            <Button
              variant="ghost"
              size="icon"
              className="absolute top-2 right-2 z-50 bg-black/50 hover:bg-black/70 text-white"
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
                <svg
                  className="absolute inset-0 w-full h-full pointer-events-none"
                  viewBox={`0 0 ${fullscreenDimensions.width} ${fullscreenDimensions.height}`}
                  preserveAspectRatio="none"
                >
                  {lineAnnotations.map((annotation) => {
                    const y = (annotation.lineY! / 100) * fullscreenDimensions.height;
                    return (
                      <line
                        key={`fullscreen-line-${annotation.id}`}
                        x1={0}
                        y1={y}
                        x2={fullscreenDimensions.width}
                        y2={y}
                        stroke={annotation.color}
                        strokeWidth="2"
                        strokeOpacity="0.8"
                      />
                    );
                  })}
                </svg>
              )}

              {/* HTML Overlay for annotation labels in fullscreen */}
              {fullscreenDimensions.width > 0 && annotations.length > 0 && (
                <div className="absolute inset-0 pointer-events-none">
                  {annotations.map((annotation) => {
                    const x = (annotation.x / 100) * fullscreenDimensions.width;
                    const y = (annotation.y / 100) * fullscreenDimensions.height;

                    return (
                      <AnnotationLabel
                        key={`fullscreen-${annotation.id}`}
                        annotation={annotation}
                        x={x}
                        y={y}
                        containerWidth={fullscreenDimensions.width}
                        isFullscreen
                      />
                    );
                  })}
                </div>
              )}
            </div>

            {/* Annotation count in fullscreen */}
            {annotations.length > 0 && (
              <div className="absolute bottom-2 left-2 text-xs text-white/70 bg-black/50 px-2 py-1 rounded">
                {annotations.length} annotations
              </div>
            )}
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
}

interface AnnotationLabelProps {
  annotation: ChartAnnotation;
  x: number;
  y: number;
  containerWidth: number;
  isFullscreen?: boolean;
}

function AnnotationLabel({ annotation, x, y, containerWidth, isFullscreen = false }: AnnotationLabelProps) {
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
          "rounded border font-medium shadow-lg",
          isFullscreen ? "px-3 py-1.5 text-sm" : "px-2 py-1 text-xs",
          getTypeStyles()
        )}
        title={annotation.description}
      >
        <div className="font-semibold truncate">{annotation.label}</div>
        {annotation.price && (
          <div className={cn("font-mono opacity-90", isFullscreen ? "text-xs" : "text-[10px]")}>
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
