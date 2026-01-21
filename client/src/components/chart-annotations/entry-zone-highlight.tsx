import { priceToY } from "./annotated-chart";

interface PriceRange {
  minPrice: number;
  maxPrice: number;
}

interface EntryZoneHighlightProps {
  entryZone: string;
  invalidationLevel: number;
  priceRange: PriceRange;
  imageWidth: number;
  imageHeight: number;
  direction: "long" | "short" | "none";
}

// Parse entry zone string like "1.2400-1.2420" or "around 1.2400"
function parseEntryZone(entryZone: string): { start: number; end: number } | null {
  // Try range format first (e.g., "1.2400-1.2420")
  const rangeMatch = entryZone.match(/(\d+\.?\d*)\s*[-–]\s*(\d+\.?\d*)/);
  if (rangeMatch) {
    return {
      start: parseFloat(rangeMatch[1]),
      end: parseFloat(rangeMatch[2]),
    };
  }

  // Try single price format (e.g., "around 1.2400" or just "1.2400")
  const singleMatch = entryZone.match(/(\d+\.?\d+)/);
  if (singleMatch) {
    const price = parseFloat(singleMatch[1]);
    // Create a small zone around the price (0.1% range)
    const buffer = price * 0.001;
    return {
      start: price - buffer,
      end: price + buffer,
    };
  }

  return null;
}

export function EntryZoneHighlight({
  entryZone,
  invalidationLevel,
  priceRange,
  imageWidth,
  imageHeight,
  direction,
}: EntryZoneHighlightProps) {
  const fontSize = Math.max(12, imageHeight * 0.02);
  const parsedZone = parseEntryZone(entryZone);

  if (!parsedZone) return null;

  const entryY1 = priceToY(parsedZone.start, priceRange, imageHeight);
  const entryY2 = priceToY(parsedZone.end, priceRange, imageHeight);
  const entryTop = Math.min(entryY1, entryY2);
  const entryHeight = Math.abs(entryY2 - entryY1);

  const invalidationY = priceToY(invalidationLevel, priceRange, imageHeight);

  // Entry zone colors
  const entryColor = direction === "long" ? "#22c55e" : direction === "short" ? "#ef4444" : "#a855f7";

  return (
    <g className="entry-zone-highlight">
      {/* Entry Zone Rectangle */}
      <rect
        x={imageWidth * 0.05}
        y={entryTop}
        width={imageWidth * 0.9}
        height={Math.max(entryHeight, 8)}
        fill={entryColor}
        fillOpacity="0.25"
        stroke={entryColor}
        strokeWidth="2"
        strokeDasharray="6 3"
      />

      {/* Entry Zone Label */}
      <rect
        x={imageWidth * 0.5 - 55}
        y={entryTop + entryHeight / 2 - (fontSize + 8) / 2}
        width={110}
        height={fontSize + 8}
        fill={entryColor}
        fillOpacity="0.95"
        rx="4"
      />
      <text
        x={imageWidth * 0.5}
        y={entryTop + entryHeight / 2}
        fill="white"
        fontSize={fontSize}
        fontWeight="700"
        textAnchor="middle"
        dominantBaseline="middle"
      >
        ENTRY ZONE
      </text>

      {/* Invalidation Level Line */}
      {invalidationLevel > 0 && invalidationY > 0 && invalidationY < imageHeight && (
        <g className="invalidation-level">
          <line
            x1={0}
            y1={invalidationY}
            x2={imageWidth}
            y2={invalidationY}
            stroke="#dc2626"
            strokeWidth="3"
            strokeDasharray="10 5"
            strokeOpacity="0.9"
          />
          {/* SL Label */}
          <rect
            x={imageWidth - 95}
            y={invalidationY - fontSize / 2 - 4}
            width={90}
            height={fontSize + 8}
            fill="#dc2626"
            rx="3"
          />
          <text
            x={imageWidth - 50}
            y={invalidationY}
            fill="white"
            fontSize={fontSize}
            fontWeight="700"
            textAnchor="middle"
            dominantBaseline="middle"
            fontFamily="monospace"
          >
            SL: {invalidationLevel.toFixed(invalidationLevel >= 100 ? 2 : 5)}
          </text>
          {/* Arrow indicating invalidation direction */}
          {direction === "long" ? (
            // For longs, invalidation is below - show down arrow
            <polygon
              points={`${imageWidth * 0.15},${invalidationY + 5} ${imageWidth * 0.15 - 8},${invalidationY + 20} ${imageWidth * 0.15 + 8},${invalidationY + 20}`}
              fill="#dc2626"
            />
          ) : direction === "short" ? (
            // For shorts, invalidation is above - show up arrow
            <polygon
              points={`${imageWidth * 0.15},${invalidationY - 5} ${imageWidth * 0.15 - 8},${invalidationY - 20} ${imageWidth * 0.15 + 8},${invalidationY - 20}`}
              fill="#dc2626"
            />
          ) : null}
        </g>
      )}
    </g>
  );
}
