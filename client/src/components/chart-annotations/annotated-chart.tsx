import { useState, useRef, useEffect } from "react";
import type { FullAnalysisResult } from "@shared/schema";
import { cn } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { LevelLines } from "./level-lines";
import { LiquidityZones } from "./liquidity-zones";
import { OrderBlockZones } from "./order-block-zones";
import { ImbalanceZones } from "./imbalance-zones";
import { EntryZoneHighlight } from "./entry-zone-highlight";
import { TargetLines } from "./target-lines";
import { AnnotationLegend } from "./annotation-legend";
import {
  Target,
  Activity,
  Layers,
  BarChart3,
  TrendingUp,
  Crosshair,
} from "lucide-react";

export interface AnnotationSettings {
  levels: boolean;
  liquidity: boolean;
  orderBlocks: boolean;
  imbalances: boolean;
  entryZone: boolean;
  targets: boolean;
}

interface AnnotatedChartProps {
  imageData: string;
  analysis: FullAnalysisResult | null;
  mode?: "full" | "entry";
  showControls?: boolean;
  className?: string;
}

interface PriceRange {
  minPrice: number;
  maxPrice: number;
}

// Calculate price range from analysis data
function calculatePriceRange(analysis: FullAnalysisResult): PriceRange {
  const prices: number[] = [];

  // Collect all prices from analysis
  if (analysis.key_levels.support_levels) {
    prices.push(...analysis.key_levels.support_levels);
  }
  if (analysis.key_levels.resistance_levels) {
    prices.push(...analysis.key_levels.resistance_levels);
  }
  if (analysis.key_levels.sr_flips) {
    prices.push(...analysis.key_levels.sr_flips);
  }
  if (analysis.liquidity.equal_highs) {
    prices.push(...analysis.liquidity.equal_highs);
  }
  if (analysis.liquidity.equal_lows) {
    prices.push(...analysis.liquidity.equal_lows);
  }
  if (analysis.impulse_origin.origin_zones) {
    analysis.impulse_origin.origin_zones.forEach((zone) => {
      prices.push(zone.start, zone.end);
    });
  }
  if (analysis.imbalance.fvg_zones) {
    analysis.imbalance.fvg_zones.forEach((zone) => {
      prices.push(zone.start, zone.end);
    });
  }
  if (analysis.entry_logic.invalidation_level) {
    prices.push(analysis.entry_logic.invalidation_level);
  }
  if (analysis.entry_logic.targets) {
    prices.push(...analysis.entry_logic.targets);
  }

  if (prices.length === 0) {
    return { minPrice: 0, maxPrice: 100 };
  }

  const minPrice = Math.min(...prices);
  const maxPrice = Math.max(...prices);

  // Add 5% padding
  const padding = (maxPrice - minPrice) * 0.05;
  return {
    minPrice: minPrice - padding,
    maxPrice: maxPrice + padding,
  };
}

// Convert price to Y coordinate (inverted because SVG Y increases downward)
export function priceToY(
  price: number,
  priceRange: PriceRange,
  imageHeight: number
): number {
  const { minPrice, maxPrice } = priceRange;
  const priceRangeVal = maxPrice - minPrice;
  if (priceRangeVal === 0) return imageHeight / 2;
  return imageHeight - ((price - minPrice) / priceRangeVal) * imageHeight;
}

export function AnnotatedChart({
  imageData,
  analysis,
  mode = "full",
  showControls = true,
  className,
}: AnnotatedChartProps) {
  const imageRef = useRef<HTMLImageElement>(null);
  const [imageDimensions, setImageDimensions] = useState({ width: 0, height: 0 });
  const [annotations, setAnnotations] = useState<AnnotationSettings>({
    levels: true,
    liquidity: true,
    orderBlocks: true,
    imbalances: true,
    entryZone: true,
    targets: true,
  });

  // Update dimensions when image loads
  useEffect(() => {
    const img = imageRef.current;
    if (!img) return;

    const updateDimensions = () => {
      setImageDimensions({
        width: img.naturalWidth || img.width,
        height: img.naturalHeight || img.height,
      });
    };

    if (img.complete) {
      updateDimensions();
    } else {
      img.addEventListener("load", updateDimensions);
      return () => img.removeEventListener("load", updateDimensions);
    }
  }, [imageData]);

  const toggleAnnotation = (key: keyof AnnotationSettings) => {
    setAnnotations((prev) => ({ ...prev, [key]: !prev[key] }));
  };

  const priceRange = analysis ? calculatePriceRange(analysis) : null;
  const hasAnnotations = analysis && priceRange && imageDimensions.height > 0;

  const annotationControls = [
    { key: "levels" as const, label: "Levels", icon: Target },
    { key: "liquidity" as const, label: "Liquidity", icon: Activity },
    { key: "orderBlocks" as const, label: "OB", icon: Layers },
    { key: "imbalances" as const, label: "FVG", icon: BarChart3 },
    { key: "entryZone" as const, label: "Entry", icon: TrendingUp },
    { key: "targets" as const, label: "Targets", icon: Crosshair },
  ];

  return (
    <div className={cn("space-y-3", className)}>
      {/* Annotation Toggle Controls */}
      {showControls && analysis && (
        <div className="flex flex-wrap gap-1.5">
          {annotationControls.map(({ key, label, icon: Icon }) => (
            <Button
              key={key}
              size="sm"
              variant={annotations[key] ? "default" : "outline"}
              onClick={() => toggleAnnotation(key)}
              className="h-7 px-2 text-xs"
            >
              <Icon className="w-3 h-3 mr-1" />
              {label}
            </Button>
          ))}
        </div>
      )}

      {/* Chart with Annotations */}
      <div className="relative rounded-lg overflow-hidden border border-border">
        <img
          ref={imageRef}
          src={`data:image/png;base64,${imageData}`}
          alt="Chart snapshot"
          className="w-full h-auto block"
        />

        {hasAnnotations && (
          <svg
            className="absolute inset-0 w-full h-full pointer-events-none"
            viewBox={`0 0 ${imageDimensions.width} ${imageDimensions.height}`}
            preserveAspectRatio="none"
          >
            {/* Define patterns */}
            <defs>
              {/* Diagonal stripe pattern for FVG */}
              <pattern
                id="fvg-pattern"
                patternUnits="userSpaceOnUse"
                width="8"
                height="8"
                patternTransform="rotate(45)"
              >
                <line
                  x1="0"
                  y1="0"
                  x2="0"
                  y2="8"
                  stroke="#eab308"
                  strokeWidth="2"
                  strokeOpacity="0.4"
                />
              </pattern>
            </defs>

            {/* Zones (rendered first, behind lines) */}
            {annotations.orderBlocks && (
              <OrderBlockZones
                zones={analysis.impulse_origin.origin_zones}
                priceRange={priceRange}
                imageWidth={imageDimensions.width}
                imageHeight={imageDimensions.height}
                direction={analysis.entry_logic.trade_direction}
              />
            )}

            {annotations.imbalances && (
              <ImbalanceZones
                zones={analysis.imbalance.fvg_zones}
                priceRange={priceRange}
                imageWidth={imageDimensions.width}
                imageHeight={imageDimensions.height}
              />
            )}

            {annotations.entryZone && analysis.entry_logic.valid_setup && (
              <EntryZoneHighlight
                entryZone={analysis.entry_logic.entry_zone}
                invalidationLevel={analysis.entry_logic.invalidation_level}
                priceRange={priceRange}
                imageWidth={imageDimensions.width}
                imageHeight={imageDimensions.height}
                direction={analysis.entry_logic.trade_direction}
              />
            )}

            {/* Lines (rendered on top) */}
            {annotations.levels && (
              <LevelLines
                supportLevels={analysis.key_levels.support_levels}
                resistanceLevels={analysis.key_levels.resistance_levels}
                srFlips={analysis.key_levels.sr_flips}
                priceRange={priceRange}
                imageWidth={imageDimensions.width}
                imageHeight={imageDimensions.height}
              />
            )}

            {annotations.liquidity && (
              <LiquidityZones
                equalHighs={analysis.liquidity.equal_highs}
                equalLows={analysis.liquidity.equal_lows}
                sweepDetected={analysis.liquidity.sweep_detected}
                priceRange={priceRange}
                imageWidth={imageDimensions.width}
                imageHeight={imageDimensions.height}
              />
            )}

            {annotations.targets && analysis.entry_logic.valid_setup && (
              <TargetLines
                targets={analysis.entry_logic.targets}
                priceRange={priceRange}
                imageWidth={imageDimensions.width}
                imageHeight={imageDimensions.height}
              />
            )}
          </svg>
        )}
      </div>

      {/* Legend */}
      {showControls && analysis && (
        <AnnotationLegend annotations={annotations} />
      )}
    </div>
  );
}
