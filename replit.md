# TradeMind - AI-Powered Trading Journal

## Overview

TradeMind is a personal trading journal application designed for MetaTrader 5 (MT5) traders. It automatically ingests trade data from MT5, stores execution details including risk metrics (MAE/MFE), and generates AI-powered trade analysis using OpenAI. The app provides a calendar-based P&L view, trade details with drawdown visualization, and performance dashboards.

## User Preferences

Preferred communication style: Simple, everyday language.

## System Architecture

### Frontend Architecture
- **Framework**: React 18 with TypeScript
- **Routing**: Wouter (lightweight alternative to React Router)
- **State Management**: TanStack React Query for server state
- **UI Components**: shadcn/ui component library built on Radix UI primitives
- **Styling**: Tailwind CSS v4 with CSS variables for theming
- **Build Tool**: Vite with custom plugins for Replit integration

**Key Frontend Patterns**:
- Custom hooks for data fetching (`useTrades`, `useCreateTrade`, `useUpdateTrade`)
- Component-based architecture with reusable UI primitives
- Mobile-responsive design with `useIsMobile` hook

### Backend Architecture
- **Runtime**: Node.js with Express
- **Language**: TypeScript with ES modules
- **API Design**: RESTful JSON API under `/api/*` prefix
- **Development**: Vite middleware for HMR in development
- **Production**: Static file serving from `dist/public`

**API Endpoints**:
- `POST /api/trades` - Ingest trades from MT5 or manual entry (with deduplication)
- `GET /api/trades` - List trades with optional date range and account filters
- `GET /api/trades/:id` - Get single trade details
- `PATCH /api/trades/:id` - Update trade metadata (notes, tags, setup)

### Data Storage
- **Database**: PostgreSQL via Drizzle ORM
- **Schema Location**: `shared/schema.ts` (shared between client/server)
- **Migrations**: Drizzle Kit with `drizzle-kit push` for schema sync

**Core Tables**:
- `users` - Basic user accounts (id, username, password)
- `trades` - Complete trade records including:
  - MT5 identity fields (deal_id, account_id) for deduplication
  - Price data (entry, close, SL, TP)
  - P&L breakdown (pnl, commission, swap, net_pnl)
  - Risk metrics (mae, mae_cash, mfe, risk, risk_cash)
  - AI analysis fields (ai_summary, ai_execution, ai_mistake, ai_improvement)

### AI Integration
- **Provider**: OpenAI GPT API
- **Purpose**: Generate per-trade analysis summaries
- **Functionality**: Analyzes trade execution quality based on MAE relative to planned risk
- **Output**: Structured JSON with summary, execution rating (Good/Bad/Neutral), mistake identification, and improvement suggestions

### Build System
- **Client**: Vite builds to `dist/public`
- **Server**: esbuild bundles to `dist/index.cjs`
- **Bundling Strategy**: Allowlist of dependencies to bundle for faster cold starts

## External Dependencies

### Database
- **PostgreSQL**: Primary data store, connection via `DATABASE_URL` environment variable
- **Drizzle ORM**: Type-safe database access with `drizzle-orm` and `drizzle-zod` for validation

### AI Services
- **OpenAI API**: Requires `OPENAI_API_KEY` environment variable
- **Model**: GPT for trade analysis generation

### Key NPM Packages
- `@tanstack/react-query` - Server state management
- `express` - HTTP server framework
- `express-session` with `connect-pg-simple` - Session management
- `zod` with `drizzle-zod` - Runtime validation and schema generation
- `date-fns` - Date manipulation for calendar views
- `recharts` - Charting library for equity curves
- `wouter` - Client-side routing