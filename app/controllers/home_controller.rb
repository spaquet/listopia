# app/controllers/home_controller.rb
class HomeController < ApplicationController
  # Skip authentication for the home page to allow public access
  skip_before_action :authenticate_user!, only: [ :index ]

  # Main landing page - shows different content based on authentication status
  def index
    if current_user
      # If user is logged in, show a personalized dashboard preview
      @recent_lists = current_user.lists.includes(:list_items)
                                 .order(updated_at: :desc)
                                 .limit(3)

      @total_lists = current_user.accessible_lists.count
      @total_items = ListItem.joins(:list)
                            .where(list: current_user.accessible_lists)
                            .count

      # Render a different layout or redirect to dashboard
      # You could redirect directly to dashboard if preferred:
      # redirect_to dashboard_path
    else
      # Show marketing content for non-authenticated users
      @features = [
        {
          icon: "check-circle",
          title: "Smart Lists",
          description: "Create dynamic lists with different item types, priorities, and due dates."
        },
        {
          icon: "users",
          title: "Real-time Collaboration",
          description: "Share lists and collaborate in real-time with your team or family."
        },
        {
          icon: "lightning-bolt",
          title: "Lightning Fast",
          description: "Built with Rails 8 and Hotwire for instant updates without page refreshes."
        }
      ]

      @testimonials = [
        {
          name: "Sarah Johnson",
          role: "Project Manager",
          content: "Listopia has transformed how our team manages projects. The real-time collaboration is amazing!"
        },
        {
          name: "Mike Chen",
          role: "Small Business Owner",
          content: "Finally, a list app that grows with my needs. Simple for personal use, powerful for business."
        }
      ]
    end
  end

  # About page (optional)
  def about
    # Static about page content
  end

  # Pricing page (optional, for future monetization)
  def pricing
    # Pricing information
  end

  # Contact page (optional)
  def contact
    # Contact form or information
  end
end
