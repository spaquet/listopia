# app/controllers/home_controller.rb
class HomeController < ApplicationController
  # Main landing page - redirects authenticated users to dashboard
  def index
    if current_user
      # Redirect authenticated users to their dashboard
      redirect_to dashboard_path
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
