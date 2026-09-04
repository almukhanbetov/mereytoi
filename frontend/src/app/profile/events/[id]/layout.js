import EventWorkspaceShell from '@/components/profile/EventWorkspaceShell';

export default async function EventLayout({ children, params }) {
  const { id } = await params;
  return <EventWorkspaceShell eventId={id}>{children}</EventWorkspaceShell>;
}
