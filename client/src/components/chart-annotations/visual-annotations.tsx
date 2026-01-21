import { useState, useRef, useEffect, useCallback } from "react";
import { cn } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogTitle,
} from "@/components/ui/dialog";
import { Maximize2, X, ZoomIn, ZoomOut, RotateCcw } from "lucide-react";

// Hide the default dialog close button in fullscreen mode
import "./visual-annotations.css";

interface VisualAnnotationsProps {
  imageData: string;
  className?: string;
}

/**
 * Simple chart viewer component - displays the chart image with zoom/pan in fullscreen.
 * No annotations overlay - AI analysis is displayed as text alongside the chart.
 */
export function VisualAnnotations({
  imageData,
  className,
}: VisualAnnotationsProps) {
  const [isFullscreen, setIsFullscreen] = useState(false);

  // Zoom and pan state for fullscreen
  const [zoom, setZoom] = useState(1);
  const [pan, setPan] = useState({ x: 0, y: 0 });
  const [isPanning, setIsPanning] = useState(false);
  const [panStart, setPanStart] = useState({ x: 0, y: 0 });
  const zoomContainerRef = useRef<HTMLDivElement>(null);

  // Reset zoom/pan when closing fullscreen
  useEffect(() => {
    if (!isFullscreen) {
      setZoom(1);
      setPan({ x: 0, y: 0 });
    }
  }, [isFullscreen]);

  // Zoom handlers
  const handleWheel = useCallback((e: React.WheelEvent) => {
    e.preventDefault();
    const delta = e.deltaY > 0 ? -0.1 : 0.1;
    setZoom(prev => Math.min(Math.max(prev + delta, 0.5), 5));
  }, []);

  const handleZoomIn = useCallback(() => {
    setZoom(prev => Math.min(prev + 0.25, 5));
  }, []);

  const handleZoomOut = useCallback(() => {
    setZoom(prev => Math.max(prev - 0.25, 0.5));
  }, []);

  const handleResetZoom = useCallback(() => {
    setZoom(1);
    setPan({ x: 0, y: 0 });
  }, []);

  // Pan handlers
  const handleMouseDown = useCallback((e: React.MouseEvent) => {
    if (zoom > 1) {
      setIsPanning(true);
      setPanStart({ x: e.clientX - pan.x, y: e.clientY - pan.y });
    }
  }, [zoom, pan]);

  const handleMouseMove = useCallback((e: React.MouseEvent) => {
    if (isPanning && zoom > 1) {
      setPan({
        x: e.clientX - panStart.x,
        y: e.clientY - panStart.y,
      });
    }
  }, [isPanning, panStart, zoom]);

  const handleMouseUp = useCallback(() => {
    setIsPanning(false);
  }, []);

  const handleMouseLeave = useCallback(() => {
    setIsPanning(false);
  }, []);

  return (
    <div className={cn("space-y-3", className)}>
      {/* Chart Image */}
      <div
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
      </div>

      {/* Fullscreen Dialog */}
      <Dialog open={isFullscreen} onOpenChange={setIsFullscreen}>
        <DialogContent className="fullscreen-chart-dialog max-w-[95vw] max-h-[95vh] w-auto h-auto p-0 bg-black/95 border-border overflow-hidden backdrop-blur-xl">
          <DialogTitle className="sr-only">Chart Fullscreen View</DialogTitle>
          <div className="relative">
            {/* Control buttons - top bar */}
            <div className="absolute top-3 left-3 right-3 z-50 flex items-center justify-between">
              {/* Zoom controls */}
              <div className="flex items-center gap-2 bg-black/70 backdrop-blur-sm rounded-lg p-1 border border-white/20">
                <Button
                  variant="ghost"
                  size="icon"
                  className="h-8 w-8 text-white hover:bg-white/20"
                  onClick={handleZoomOut}
                  disabled={zoom <= 0.5}
                >
                  <ZoomOut className="w-4 h-4" />
                </Button>
                <span className="text-white text-sm font-mono min-w-[50px] text-center">
                  {Math.round(zoom * 100)}%
                </span>
                <Button
                  variant="ghost"
                  size="icon"
                  className="h-8 w-8 text-white hover:bg-white/20"
                  onClick={handleZoomIn}
                  disabled={zoom >= 5}
                >
                  <ZoomIn className="w-4 h-4" />
                </Button>
                <div className="w-px h-5 bg-white/20" />
                <Button
                  variant="ghost"
                  size="icon"
                  className="h-8 w-8 text-white hover:bg-white/20"
                  onClick={handleResetZoom}
                  title="Reset zoom"
                >
                  <RotateCcw className="w-4 h-4" />
                </Button>
              </div>

              {/* Close button */}
              <Button
                variant="ghost"
                size="icon"
                className="bg-black/70 hover:bg-black/90 text-white border border-white/20"
                onClick={() => setIsFullscreen(false)}
              >
                <X className="w-5 h-5" />
              </Button>
            </div>

            {/* Zoom hint */}
            {zoom === 1 && (
              <div className="absolute top-16 left-1/2 -translate-x-1/2 z-40 bg-black/60 text-white/70 text-xs px-3 py-1.5 rounded-full backdrop-blur-sm border border-white/10">
                Scroll to zoom • Drag to pan when zoomed
              </div>
            )}

            {/* Zoomable/pannable container */}
            <div
              ref={zoomContainerRef}
              className={cn(
                "overflow-hidden",
                zoom > 1 ? "cursor-grab" : "cursor-default",
                isPanning && "cursor-grabbing"
              )}
              onWheel={handleWheel}
              onMouseDown={handleMouseDown}
              onMouseMove={handleMouseMove}
              onMouseUp={handleMouseUp}
              onMouseLeave={handleMouseLeave}
            >
              {/* Fullscreen chart */}
              <div
                className="relative transition-transform duration-100"
                style={{
                  transform: `scale(${zoom}) translate(${pan.x / zoom}px, ${pan.y / zoom}px)`,
                  transformOrigin: "center center",
                }}
              >
                <img
                  src={`data:image/png;base64,${imageData}`}
                  alt="Chart snapshot fullscreen"
                  className="max-w-[95vw] max-h-[90vh] w-auto h-auto block select-none"
                  draggable={false}
                />
              </div>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
}
